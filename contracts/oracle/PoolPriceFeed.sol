// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "../interface/IPoolPriceFeed.sol";
import "../interface/IPriceFeed.sol";
import "../interface/IPancakePair.sol";
import "../Admin.sol";

contract PoolPriceFeed is IPoolPriceFeed,Admin {

    // 预言机地址（本地会采用mock的方式）
    IPriceFeed ipriceFeed;
    // Amm 价格数据  (本地采用mock的方式)
    IPancakePair iPancakPair;

    uint256 public PRICE_PRECISION = 10 ** 30;
    uint256 public ONE_USD = PRICE_PRECISION;
    uint256 public MAX_ADJUSTMENT_BASIS_POINTS = 20 ;
    uint256 public BASIS_POINTS_DIVISOR = 10000; 
    uint256 public MAX_SPREAD_BASIS_POINTS = 50;

    bool isAmmEnabled;
    bool favorPrimaryPrice = false;
    uint256 public maxStrictPriceDeviation = 0;
    uint256 public spreadThresholdBasisPoints = 30;
    uint256 public priceSampleSpace = 3;
    address bnb;
    address eth;
    address btc;
    address bnbBusd;
    address btcBnb;
    address ethBnb;

    mapping(address => uint256) adjustmentBasisPoints;
    mapping(address => bool) isAdjustmentAdditive;
    mapping(address => bool) strictStableTokens;
    mapping(address => uint256) spreadBasisPoints;
    mapping(address => address) priceFeeds;
    mapping(address => uint256) priceDecimals;


    constructor () {
        admins.push(msg.sender);
        isAdmin[msg.sender]=true;
    }

     function setAdjustment(address _token, bool _isAdditive, uint256 _adjustmentBps) external onlyAdmin {
        
        require(_adjustmentBps <= MAX_ADJUSTMENT_BASIS_POINTS, "invalid _adjustmentBps");
        isAdjustmentAdditive[_token] = _isAdditive;
        adjustmentBasisPoints[_token] = _adjustmentBps;
    }

    function setIsAmmEnabled(bool _isEnabled) external onlyAdmin {
        isAmmEnabled = _isEnabled;
    }

    function setTokens(address _btc, address _eth, address _bnb) external onlyAdmin {
        btc = _btc;
        eth = _eth;
        bnb = _bnb;
    }

    function setPairs(address _bnbBusd, address _ethBnb, address _btcBnb) external onlyAdmin {
        bnbBusd = _bnbBusd;
        ethBnb = _ethBnb;
        btcBnb = _btcBnb;
    }

    function setSpreadBasisPoints(address _token, uint256 _spreadBasisPoints) external onlyAdmin {
        require(_spreadBasisPoints <= MAX_SPREAD_BASIS_POINTS, "VaultPriceFeed: invalid _spreadBasisPoints");
        spreadBasisPoints[_token] = _spreadBasisPoints;
    }

    function setSpreadThresholdBasisPoints(uint256 _spreadThresholdBasisPoints) external onlyAdmin {
        spreadThresholdBasisPoints = _spreadThresholdBasisPoints;
    }

    function setFavorPrimaryPrice(bool _favorPrimaryPrice) external onlyAdmin {
        favorPrimaryPrice = _favorPrimaryPrice;
    }

    function setPriceSampleSpace(uint256 _priceSampleSpace) external onlyAdmin {
        require(_priceSampleSpace > 0, "VaultPriceFeed: invalid _priceSampleSpace");
        priceSampleSpace = _priceSampleSpace;
    }

    function setMaxStrictPriceDeviation(uint256 _maxStrictPriceDeviation) external onlyAdmin {
        maxStrictPriceDeviation = _maxStrictPriceDeviation;
    }

    function setTokenConfig(
        address _token,
        address _priceFeed,
        uint256 _priceDecimals,
        bool _isStrictStable
    ) external onlyAdmin {
        priceFeeds[_token] = _priceFeed;
        priceDecimals[_token] = _priceDecimals;
        strictStableTokens[_token] = _isStrictStable;
    }


    function getPrice(
        address _token,
        bool _maximise,
        bool _includeAmmPrice
    ) external view override returns (uint256) {
        uint256 price = getPrimaryPrice(_token, _maximise);
        if (_includeAmmPrice && isAmmEnabled) {
            price = getAmmPrice(_token, _maximise, price);
        }

        if (strictStableTokens[_token]) {
            uint256 delta = price > ONE_USD ? price-ONE_USD : ONE_USD-price;
            if (delta <= maxStrictPriceDeviation) {
                return ONE_USD;
            }

            // if _maximise and price is e.g. 1.02, return 1.02
            if (_maximise && price > ONE_USD) {
                return price;
            }

            // if !_maximise and price is e.g. 0.98, return 0.98
            if (!_maximise && price < ONE_USD) {
                return price;
            }

            return ONE_USD;
        }
        
        uint256 _spreadBasisPoints = spreadBasisPoints[_token];

        if (_maximise) {
            return price*(BASIS_POINTS_DIVISOR+_spreadBasisPoints)/(BASIS_POINTS_DIVISOR);
        }

        return price*(BASIS_POINTS_DIVISOR-_spreadBasisPoints)/(BASIS_POINTS_DIVISOR);

    }

    function getPrimaryPrice(address _token,bool _maximise) public view returns (uint256){
        address priceFeedAddress = priceFeeds[_token];
        require(priceFeedAddress != address(0), "VaultPriceFeed: invalid price feed");
        
        IPriceFeed priceFeed = IPriceFeed(priceFeedAddress);

        uint256 price = 0;
        uint256 roundId = priceFeed.latestRound();

        for (uint256 i = 0; i < priceSampleSpace; i++) {
            if (roundId <= i) { break; }
            uint256 p;

            if (i == 0) {
                int256 _p = priceFeed.latestAnswer();
                require(_p > 0, "VaultPriceFeed: invalid price");
                p = uint256(_p);
            } else {
                (, int256 _p, , ,) = priceFeed.getRoundData(roundId - i);
                require(_p > 0, "VaultPriceFeed: invalid price");
                p = uint256(_p);
            }

            if (price == 0) {
                price = p;
                continue;
            }

            if (_maximise && p > price) {
                price = p;
                continue;
            }

            if (!_maximise && p < price) {
                price = p;
            }
        }

        require(price > 0, "VaultPriceFeed: could not fetch price");
        uint256 _priceDecimals = priceDecimals[_token];
        return price*PRICE_PRECISION/(10 ** _priceDecimals);
    }

    function getAmmPrice(address _token, bool _maximise,uint256 _price) public view returns (uint256){
        uint256 ammPrice;
        
        if (_token == bnb) {
            ammPrice = getPairPrice(bnbBusd, true);
        }

        if (_token == eth) {
            uint256 price0 = getPairPrice(bnbBusd, true);
            uint256 price1 = getPairPrice(ethBnb, true);
            ammPrice = price0*price1/(PRICE_PRECISION);
        }

        if (_token == btc) {
            uint256 price0 = getPairPrice(bnbBusd, true);
            uint256 price1 = getPairPrice(btcBnb, true);
            ammPrice = price0*price1/PRICE_PRECISION;
        }

        if(ammPrice == 0){
            return _price;
        }

        uint256 diff = ammPrice > _price ? ammPrice-_price : _price-ammPrice;
        if (diff*(BASIS_POINTS_DIVISOR) < _price*spreadThresholdBasisPoints) {
            if (favorPrimaryPrice) {
                return _price;
            }
            return ammPrice;
        }

        if (_maximise && ammPrice > _price) {
            return ammPrice;
        }

        if (!_maximise && ammPrice < _price) {
            return ammPrice;
        }

        return _price;
    }


    function getPairPrice(address _pair, bool _divByReserve0) internal view returns (uint256) {
        (uint256 reserve0, uint256 reserve1, ) = IPancakePair(_pair).getReserves();
        if (_divByReserve0) {
            if (reserve0 == 0) { return 0; }
            return reserve1*PRICE_PRECISION/reserve0;
        }
        if (reserve1 == 0) { return 0; }
        return reserve0*PRICE_PRECISION/reserve1;
    }


}