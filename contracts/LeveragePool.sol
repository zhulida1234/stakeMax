//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./interface/IPoolPriceFeed.sol";
import "./utils/ReentrancyGuard.sol";
import "./interface/IERC20.sol";
import "./Admin.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";


contract LeveragePool is ReentrancyGuard,Admin,Initializable,UUPSUpgradeable,AccessControlUpgradeable,PausableUpgradeable{

    struct Position{
        // 头寸大小
        uint256 positionSize;
        // 抵押物
        uint256 collateral;
        // 平均价格
        uint256 averagePrice;
        // 资金利率
        uint256 entryFundingRate;
        // 仓位中的储备资金
        uint256 reserveAmount;
        // 已实现的盈亏
        int256 realisedPnl;
        // 最后一次更新时间
        uint256 lastUpdateTime;
    }

    IPoolPriceFeed iPoolPriceFeed;

    uint256 public constant BASIS_POINTS_DIVISOR = 10000;
    uint256 public constant FUNDING_RATE_PRECISION = 1000000;

    // 是否启用杠杆,若不启动,则直接报错
    bool public isLeverageEnabled;
    // 是否应该更新累积利率
    bool public shouldUpdate;
    // 是否包含自动做市商价格
    bool public includeAmmPrice;
    // 是否开启清算模式
    bool public inPrivateLiquidationMode;
    // 最大燃气限制
    uint256 public maxGasPrice;
    // 最后一次更新的周期
    uint256 public fundingInterval;
    // 稳定币利率因子
    uint256 public stableFundingRateFactor;
    // 资金利率因子
    uint256 public fundingRateFactor;
    // 最小盈利时间区间
    uint256 public minProfitTime;
    // 保证金费用基点
    uint256 public marginFeeBasisPoints = 10;
    // 清算费用(美元计价)
    uint256 public liquidationFeeUsd;
    // 最大杠杆
    uint256 public maxLeverage;

    // 代币白名单
    mapping(address=>bool) tokenWhiteList;
    // 代币是否为稳定币
    mapping(address=>bool) stableTokens;
    // 代币是否能被做空
    mapping(address=>bool) shortableTokens;
    // 代币最后一次更新资金的时间周期
    mapping(address=>uint256) lastFundingTimes;
    // 代币累积的资金利率
    mapping(address=>uint256) cumulativeFundingRates;
    // 代币的余额池子
    mapping(address=>uint256) poolAmounts;
    // 预留资金池子
    mapping(address=>uint256) reservedAmounts;
    // 不同的交易机制对应的仓位
    mapping(bytes32=>Position) positions;
    // 最小盈利点数
    mapping(address=>uint256) minProfitBasisPoints;
    // 代币的前一余额
    mapping(address=>uint256) tokenBalance;
    // 代币手续费存储
    mapping(address=>uint256) feeReserves;
    // 代币精度
    mapping(address=>uint256) tokenDecimal;
    // 代币扣除抵押后的金额
    mapping(address=>uint256) guaranteedUsds;
    // 全局空头头寸
    mapping(address=>uint256) globalShortSizes;
    // 全局空头平均价格
    mapping(address=>uint256) globalShortAveragePrices; 
    // 存储是否是清算者
    mapping(address=>bool) isLiquidator;

    event UpdateFundingRate(address _collateralToken, uint256 cumulativeFundRate);
    event CollectMarginFees(address _collateralToken, uint256 feeUsd, uint256 feeTokens);
    event IncreaseReservedAmount(address _token, uint256 _amount);
    event DecreaseReservedAmount(address _token, uint256 _amount);
    event IncreaseGuaranteedUsds(address _token, uint256 _amount);
    event DecreaseGuaranteedUsds(address _token, uint256 _amount);
    event IncreasePoolAmount(address _token, uint256 _amount);
    event DecreasePoolAmount(address _token, uint256 _amount);
    event IncreaseGlobalShortSize(address _token,uint256 _amount);
    event DecreaseGlobalShortSize(address _token,uint256 _amount);

    event IncreasePosition(bytes32 key, address _account, address _collateralToken, address _indexToken, uint256 _collateralDeltaUsd, uint256 _sizeDelta, bool _isLong, uint256 _price, uint256 fee);
    event DecreasePosition(bytes32 key, address _account, address _collateralToken, address _indexToken, uint256 _collateralDeltaUsd, uint256 _sizeDelta, bool _isLong, uint256 _price, uint256 fee);

    event UpdatePosition(bytes32 key, uint256 _positionSize, uint256 _collateral, uint256 _averagePrice, uint256 _entryFundingRate, uint256 reserveAmount, uint256 _price);
    event ClosePosition(bytes32 key, uint256 _positionSize, uint256 _collateral, uint256 _averagePrice, uint256 _entryFundingRate);

    event LiquidatePosition(bytes32 key, address _account, address _collateralToken, address _indexToken, bool _isLong, uint256 positionSize, uint256 positionCollateral, uint256 reserveAmount, uint256 markPrice);


    // 构造函数，初始化奖励代币数量 
    function initialize(address _priceFeedAddress,uint256 _maxGasPrice,bool _shouldUpdate,bool _includeAmmPrice,bool _inPrivateLiquidationMode) external initializer {
        iPoolPriceFeed = IPoolPriceFeed(_priceFeedAddress);
        maxGasPrice = _maxGasPrice;
        shouldUpdate = _shouldUpdate;
        includeAmmPrice = _includeAmmPrice;
        inPrivateLiquidationMode = _inPrivateLiquidationMode;

        addAdmin(msg.sender);
        __UUPSUpgradeable_init();
    }

    //初始化设置
    function setConfig(uint256 _fundingInterval,uint256 _stableFundingRateFactor,uint256 _fundingRateFactor,uint256 _minProfitTime,uint256 _marginFeeBasisPoints,uint256 _liquidationFeeUsd,uint256 _maxLeverage) external onlyAdmin{
        fundingInterval = _fundingInterval;
        stableFundingRateFactor = _stableFundingRateFactor;
        fundingRateFactor = _fundingRateFactor;
        minProfitTime = _minProfitTime;
        marginFeeBasisPoints = _marginFeeBasisPoints;
        liquidationFeeUsd = _liquidationFeeUsd;
        maxLeverage =_maxLeverage;
    }

    
    function setMaxGasPrice(uint256 _maxGasPrice) external onlyAdmin {
        maxGasPrice = _maxGasPrice;
    }

    function addWhiteList(address _whiteAddress) external onlyAdmin {
        tokenWhiteList[_whiteAddress] = true;
    }

    function setStableToken(address _stableToken) external onlyAdmin {
        stableTokens[_stableToken] = true;
    }

    function setShortableToken(address _shortableToken) external onlyAdmin {
        shortableTokens[_shortableToken] = true;
    }

    function setIsLiquidator(address _address) external onlyAdmin {
        isLiquidator[_address] = true;
    }

    function setMinProfitBasisPoints(address _token,uint256 _points) external onlyAdmin {
        minProfitBasisPoints[_token] = _points;
    }

    function setTokenDecimals(address _token,uint256 _decimal) external onlyAdmin {
        tokenDecimal[_token] = _decimal;
    }

    function setShouldUpdateRate(bool _shouldUpdate) external onlyAdmin {
        shouldUpdate = _shouldUpdate;
    }

    function setFundingInterval(uint256 _fundingInterval) external onlyAdmin {
        fundingInterval = _fundingInterval;
    }

    function setInPrivateLiquidationMode(bool _inPrivateLiquidationMode) external onlyAdmin {
        inPrivateLiquidationMode = _inPrivateLiquidationMode;
    }

    function setStableFundingRateFactor(uint256 _stableFundingRateFactor) external onlyAdmin {
        stableFundingRateFactor = _stableFundingRateFactor;
    }

    function setFundingRateFactor(uint256 _fundingRateFactor) external onlyAdmin {
        fundingRateFactor = _fundingRateFactor;
    }

    function setMinProfitTime(uint256 _minProfitTime) external onlyAdmin {
        minProfitTime = _minProfitTime;
    }

    function setMarginFeeBasisPoints(uint256 _marginFeeBasisPoints) external onlyAdmin {
       marginFeeBasisPoints = _marginFeeBasisPoints;
    }

    function setLiquidationFeeUsd(uint256 _liquidationFeeUsd ) external  onlyAdmin {
        liquidationFeeUsd = _liquidationFeeUsd;
    }

    function setMaxLeverage(uint256 _maxLeverage) external onlyAdmin {
        maxLeverage = _maxLeverage;
    }

    /**
     * 加码
     * @param _account 对应账户
     * @param _collateralToken 抵押token
     * @param _indexToken 索引token
     * @param _sizeDelta 增加头寸
     * @param _isLong true为多头，false为空头
     */
    function increasePosition(address _account, address _collateralToken, address _indexToken, uint256 _sizeDelta, bool _isLong) external nonReentrant {
        // 校验是否启用了杠杆
        require(isLeverageEnabled, "leverage should be turn on");
        // 校验当前的gas小于最大的gas费率
        _validateGasPrice();
        // 验证代币是否合法
        _validateTokens(_collateralToken, _indexToken, _isLong);
        // 更新累积融资利率
        updateCumulativeFundingRate(_collateralToken);

        bytes32 key = getPositionKey(_account, _collateralToken, _indexToken, _isLong);
        Position storage position = positions[key];
        // 如果是多头，价格就用最大价格，否则就用最低价格
        uint256 price = _isLong ? getMaxPrice(_indexToken) : getMinPrice(_indexToken);

        if (position.positionSize == 0) {
            // 初始头寸，就用获取的预测价格
            position.averagePrice = price;
        }

        if (position.positionSize > 0 && _sizeDelta > 0) {
            // 多头 nextSize * nextPrice / nextSize + 盈利  空头 nextSize * nextPrice / nextSize - 盈利
            position.averagePrice = getNextAveragePrice(_indexToken, position.positionSize, position.averagePrice, _isLong, price, _sizeDelta, position.lastUpdateTime);
        }
        // 收取保证金费用
        uint256 fee = _collectMarginFees(_collateralToken, _sizeDelta, position.positionSize, position.entryFundingRate);
        // 获取抵押token的移出数量
        uint256 collateralDelta = _transferIn(_collateralToken);
        // 将抵押token转换成USD等值
        uint256 collateralDeltaUsd = tokenToUsdMin(_collateralToken, collateralDelta);
        // 增加抵押
        position.collateral = position.collateral+(collateralDeltaUsd);
        require(position.collateral >= fee, "collateral must great than fee");
        // 抵押中扣除保证金
        position.collateral = position.collateral-(fee);
        // 从cumulativeFundingRates mapping中取数
        position.entryFundingRate = cumulativeFundingRates[_collateralToken];
        // 头寸增加
        position.positionSize = position.positionSize+_sizeDelta;
        // 记录最后一次增加时间
        position.lastUpdateTime = block.timestamp;


        require(position.positionSize > 0, "positionSize can't be 0");
        // 验证头寸和抵押品的数量
        _validatePosition(position.positionSize, position.collateral);
        // 校验流动性 
        validateLiquidation(_account, _collateralToken, _indexToken, _isLong);

        // reserve tokens to pay profits on the position
        // 根据抵押token 和 头寸,获取最大数量的USDG
        uint256 reserveDelta = usdToTokenMax(_collateralToken, _sizeDelta);
        // position中增加储备金
        position.reserveAmount = position.reserveAmount+reserveDelta;
        // 池子中增加储备金
        _increaseReservedAmount(_collateralToken, reserveDelta);

        if (_isLong) {
            // guaranteedUsd stores the sum of (position.size - position.collateral) for all positions
            // if a fee is charged on the collateral then guaranteedUsd should be increased by that fee amount
            // since (position.size - position.collateral) would have increased by `fee`
            _increaseGuaranteedUsd(_collateralToken, _sizeDelta+fee);
            _decreaseGuaranteedUsd(_collateralToken, collateralDeltaUsd);
            // treat the deposited collateral as part of the pool
            // 往抵押token池子中增加 移出数量 _transferIn
            _increasePoolAmount(_collateralToken, collateralDelta);
            // fees need to be deducted from the pool since fees are deducted from position.collateral
            // and collateral is treated as part of the pool
            // 往抵押token池子中减少 根据fee计算出最小的数量
            _decreasePoolAmount(_collateralToken, usdToTokenMin(_collateralToken, fee));
        } else {
            // 更新空头全局平均价格
            if (globalShortSizes[_indexToken] == 0) {
                globalShortAveragePrices[_indexToken] = price;
            } else {
                globalShortAveragePrices[_indexToken] = getNextGlobalShortAveragePrice(_indexToken, price, _sizeDelta);
            }
            // 增加全局空头头寸
            _increaseGlobalShortSize(_indexToken, _sizeDelta);
        }

        emit IncreasePosition(key, _account, _collateralToken, _indexToken, collateralDeltaUsd, _sizeDelta, _isLong, price, fee);
        emit UpdatePosition(key, position.positionSize, position.collateral, position.averagePrice, position.entryFundingRate, position.reserveAmount, price);
    }

    /**
     * 减仓
     * @param _account 对应账户
     * @param _collateralToken 抵押token地址
     * @param _indexToken 索引token地址
     * @param _sizeDelta 减少仓位的头寸
     * @param _isLong true为多头, false为空头
     */
    function decreasePosition(address _account, address _collateralToken, address _indexToken, uint256 _collateralDelta, uint256 _sizeDelta, bool _isLong, address _receiver) external nonReentrant returns (uint256){
        _validateGasPrice();
        
        // 更新累积融资利率
        updateCumulativeFundingRate(_collateralToken);

        //获取对应账户的仓位，并校验相关参数
        bytes32 key = getPositionKey(_account, _collateralToken, _indexToken, _isLong);
        Position storage position = positions[key];
        require(position.positionSize >= _sizeDelta, "positionSize must great than _sizeDelta");
        require(position.collateral >= _collateralDelta, "positionCollateral must grate than _collateralDelta");

        uint256 collateral = position.collateral;
        // scrop variables to avoid stack too deep errors
        {
            // 减少储备金 包括个人仓位 和 池子
        uint256 reserveDelta = position.reserveAmount*_sizeDelta/(position.positionSize);
        position.reserveAmount = position.reserveAmount-reserveDelta;
        _decreaseReservedAmount(_collateralToken, reserveDelta);
        }
        // 减少抵押 和 计算手续费 // usdOut是 减少抵押折算成美元的金额 usdOutAfterFee 是usdOut扣除手续费后的金额
        (uint256 usdOut, uint256 usdOutAfterFee) = _reduceCollateral(_account, _collateralToken, _indexToken, _collateralDelta, _sizeDelta, _isLong);

        if (position.positionSize != _sizeDelta) {
            //从cumulativeFundingRates mapping中取数
            position.entryFundingRate = cumulativeFundingRates[_collateralToken];
            //减少头寸
            position.positionSize = position.positionSize-_sizeDelta;
            // 需要保证降低后的头寸，依然要大于抵押
            _validatePosition(position.positionSize, position.collateral);
            // 校验流动性
            validateLiquidation(_account, _collateralToken, _indexToken, _isLong);

            if (_isLong) {
                // 多头，需要在GuaranteedUsd 中增加抵押数据
                _increaseGuaranteedUsd(_collateralToken, collateral-position.collateral);
                // 同时，再减去 需要降低的头寸
                _decreaseGuaranteedUsd(_collateralToken, _sizeDelta);
            }

            uint256 price = _isLong ? getMinPrice(_indexToken) : getMaxPrice(_indexToken);
            emit DecreasePosition(key, _account, _collateralToken, _indexToken, _collateralDelta, _sizeDelta, _isLong, price, usdOut-(usdOutAfterFee));
            emit UpdatePosition(key, position.positionSize, position.collateral, position.averagePrice, position.entryFundingRate, position.reserveAmount, price);
        } else {
            if (_isLong) {
                // 先增加抵押，在再减去 需要降低的头寸
                _increaseGuaranteedUsd(_collateralToken, collateral);
                _decreaseGuaranteedUsd(_collateralToken, _sizeDelta);
            }

            uint256 price = _isLong ? getMinPrice(_indexToken) : getMaxPrice(_indexToken);
            emit DecreasePosition(key, _account, _collateralToken, _indexToken, _collateralDelta, _sizeDelta, _isLong, price, usdOut-(usdOutAfterFee));
            emit ClosePosition(key, position.positionSize, position.collateral, position.averagePrice, position.entryFundingRate);
            // 删除仓位
            delete positions[key];
        }

        if (!_isLong) {
            // 减少全局空头头寸大小
            _decreaseGlobalShortSize(_indexToken, _sizeDelta);
        }

        if (usdOut > 0) {
            if (_isLong) {
                // 如果是多头，需要降低池子中的数量，根据usdOut计算出最小的份额数量
                _decreasePoolAmount(_collateralToken, usdToTokenMin(_collateralToken, usdOut));
            }
            // 计算出需要转移出去的多少token（根据扣除手续费后的数量进行计算）
            uint256 amountOutAfterFees = usdToTokenMin(_collateralToken, usdOutAfterFee);
            _transferOut(_collateralToken, amountOutAfterFees, _receiver);
            return amountOutAfterFees;
        }

        return 0;
    }


    /**
     * 清算
     * @param _account 对应账户
     * @param _collateralToken 抵押token地址
     * @param _indexToken 索引token地址
     * @param _isLong true为多头, false为空头
     * @param _feeReceiver 清算接收者的地址
     */
    function liquidatePosition(address _account, address _collateralToken, address _indexToken, bool _isLong, address _feeReceiver) external nonReentrant {
        if (inPrivateLiquidationMode) {
            require(isLiquidator[msg.sender], "only liquidator can execute");
        }

        // set includeAmmPrice to false to prevent manipulated liquidations
        includeAmmPrice = false;
        //更新累积融资利率
        updateCumulativeFundingRate(_collateralToken);

        bytes32 key = getPositionKey(_account, _collateralToken, _indexToken, _isLong);
        Position memory position = positions[key];
        require(position.positionSize > 0, "postionSize must great than 0");

        (uint256 liquidationState, uint256 marginFees) = validateLiquidation(_account, _collateralToken, _indexToken, _isLong);
        // 验证清算状态
        require(liquidationState != 0, "Invalid liquidation state");
        if (liquidationState == 2) {
            // max leverage exceeded but there is collateral remaining after deducting losses so decreasePosition instead
            _decreasePosition(_account, _collateralToken, _indexToken, 0, position.positionSize, _isLong, _account);
            includeAmmPrice = true;
            return;
        }
        // 收取保证金费用，将其添加到费用储备中
        uint256 feeTokens = usdToTokenMin(_collateralToken, marginFees);
        feeReserves[_collateralToken] = feeReserves[_collateralToken]+(feeTokens);
        emit CollectMarginFees(_collateralToken, marginFees, feeTokens);

        // 减少保留金额和担保的USD
        _decreaseReservedAmount(_collateralToken, position.reserveAmount);
        if (_isLong) {
            _decreaseGuaranteedUsd(_collateralToken, position.positionSize-(position.collateral));
            _decreasePoolAmount(_collateralToken, usdToTokenMin(_collateralToken, marginFees));
        }

        // 记录清算事件，包括仓位信息和当前价格。
        uint256 markPrice = _isLong ? getMinPrice(_indexToken) : getMaxPrice(_indexToken);
        emit LiquidatePosition(key, _account, _collateralToken, _indexToken, _isLong, position.positionSize, position.collateral, position.reserveAmount,  markPrice);

        //如果是空头,同时持仓费用 < 抵押费用 , 仓位抵押减少持仓费用, 同时池子中 增加剩余的数量
        if (!_isLong && marginFees < position.collateral) {
            uint256 remainingCollateral = position.collateral-(marginFees);
            _increasePoolAmount(_collateralToken, usdToTokenMin(_collateralToken, remainingCollateral));
        }

        if (!_isLong) {
            // 降低全局空头头寸
            _decreaseGlobalShortSize(_indexToken, position.positionSize);
        }
        // 删除仓位
        delete positions[key];

        // pay the fee receiver using the pool, we assume that in general the liquidated amount should be sufficient to cover
        // the liquidation fees
        // 支付清算费用给接收者：
        _decreasePoolAmount(_collateralToken, usdToTokenMin(_collateralToken, liquidationFeeUsd));
        _transferOut(_collateralToken, usdToTokenMin(_collateralToken, liquidationFeeUsd), _feeReceiver);

        includeAmmPrice = true;
    }  

    function getMaxPrice(address _indexToken) internal view returns (uint256){
        return iPoolPriceFeed.getPrice(_indexToken,true,includeAmmPrice);
    }

    function getMinPrice(address _indexToken) internal view returns (uint256){
        return iPoolPriceFeed.getPrice(_indexToken,false,includeAmmPrice);
    }

    function _validateGasPrice() private view {
        require(tx.gasprice <= maxGasPrice,"the gas overFlow limit");
    }


    function _validateTokens(address _collateralToken, address _indexToken, bool _isLong) private view {
       // 多头时,必须抵押和索引保持一致
       if (_isLong) {
            require(_collateralToken == _indexToken, "collateral token must equal target token");
            require(tokenWhiteList[_collateralToken], "collateral token not in whiteList");
            require(!stableTokens[_collateralToken], "token can't be stable");
            return;
        }

        require(tokenWhiteList[_collateralToken], "collateral token not in whiteList");
        require(stableTokens[_collateralToken], "collateral token should be stable");
        require(!stableTokens[_indexToken], "indexToken can't be stable");
        require(shortableTokens[_indexToken], "indexToken can't be shortable");
    }

    function _validatePosition(uint256 _positionSize, uint256 _collateral) private pure {
        if (_positionSize == 0) {
            require(_collateral == 0, "init Position collateral must be 0");
            return;
        }
        require(_positionSize >= _collateral, "the positionSize should great than collateral");
    }

    function _transferIn(address _collateralToken) private returns (uint256){
        uint256 preBalance = tokenBalance[_collateralToken];
        uint256 currentBalance = IERC20(_collateralToken).balanceOf(address(this));

        tokenBalance[_collateralToken] = currentBalance;
        return currentBalance-preBalance;
    }

    function _transferOut(address _collateralToken, uint256 amountOutAfterFees, address _receiver) private {
        IERC20(_collateralToken).transfer(_receiver,amountOutAfterFees);
        tokenBalance[_collateralToken] = IERC20(_collateralToken).balanceOf(address(this));
    }

    function _collectMarginFees(address _collateralToken, uint256 _sizeDelta, uint256 _positioSize, uint256 _entryFundingRate) private returns (uint256){
        uint256 feeUsd = getPositionFee(_sizeDelta);

        uint256 fundingFee = getFundingFee(_collateralToken, _positioSize, _entryFundingRate);
        feeUsd = feeUsd-(fundingFee);

        uint256 feeTokens = usdToTokenMin(_collateralToken, feeUsd);
        feeReserves[_collateralToken] = feeReserves[_collateralToken]+(feeTokens);

        emit CollectMarginFees(_collateralToken, feeUsd, feeTokens);
        return feeUsd;
    }

    // 降低抵押  TODO
    function _reduceCollateral(address _account, address _collateralToken, address _indexToken, uint256 _collateralDelta, uint256 _sizeDelta, bool _isLong) private returns (uint256 ,uint256){
        bytes32 key = getPositionKey(_account, _collateralToken, _indexToken, _isLong);
        Position storage position = positions[key];

        uint256 fee = _collectMarginFees(_collateralToken, _sizeDelta, position.positionSize, position.entryFundingRate);
        bool hasProfit;
        uint256 adjustedDelta;

        // scope variables to avoid stack too deep errors
        {
        (bool _hasProfit, uint256 delta) = getDelta(_indexToken, position.positionSize, position.averagePrice, _isLong, position.lastUpdateTime);
        hasProfit = _hasProfit;
        // get the proportional change in pnl
        adjustedDelta = _sizeDelta*(delta)/(position.positionSize);
        }

        uint256 usdOut;
        // transfer profits out
        if (hasProfit && adjustedDelta > 0) {
            usdOut = adjustedDelta;
            position.realisedPnl = position.realisedPnl + int256(adjustedDelta);

            // pay out realised profits from the pool amount for short positions
            if (!_isLong) {
                uint256 tokenAmount = usdToTokenMin(_collateralToken, adjustedDelta);
                _decreasePoolAmount(_collateralToken, tokenAmount);
            }
        }

        if (!hasProfit && adjustedDelta > 0) {
            position.collateral = position.collateral-(adjustedDelta);

            // transfer realised losses to the pool for short positions
            // realised losses for long positions are not transferred here as
            // _increasePoolAmount was already called in increasePosition for longs
            if (!_isLong) {
                uint256 tokenAmount = usdToTokenMin(_collateralToken, adjustedDelta);
                _increasePoolAmount(_collateralToken, tokenAmount);
            }

            position.realisedPnl = position.realisedPnl - int256(adjustedDelta);
        }

        // reduce the position's collateral by _collateralDelta
        // transfer _collateralDelta out
        if (_collateralDelta > 0) {
            usdOut = usdOut+(_collateralDelta);
            position.collateral = position.collateral-(_collateralDelta);
        }

        // if the position will be closed, then transfer the remaining collateral out
        if (position.positionSize == _sizeDelta) {
            usdOut = usdOut+(position.collateral);
            position.collateral = 0;
        }

        // if the usdOut is more than the fee then deduct the fee from the usdOut directly
        // else deduct the fee from the position's collateral
        uint256 usdOutAfterFee = usdOut;
        if (usdOut > fee) {
            usdOutAfterFee = usdOut-(fee);
        } else {
            position.collateral = position.collateral-(fee);
            if (_isLong) {
                uint256 feeTokens = usdToTokenMin(_collateralToken, fee);
                _decreasePoolAmount(_collateralToken, feeTokens);
            }
        }

        return (usdOut, usdOutAfterFee);
    }

    function _decreasePosition(address _account, address _collateralToken, address _indexToken, uint256 _collateralDelta, uint256 _sizeDelta, bool _isLong, address _receiver) private returns (uint256) {
        // 更新累积融资利率
        updateCumulativeFundingRate(_collateralToken);

        //获取对应账户的仓位，并校验相关参数
        bytes32 key = getPositionKey(_account, _collateralToken, _indexToken, _isLong);
        Position storage position = positions[key];
        require(position.positionSize >= _sizeDelta, "positionSize must great than _sizeDelta");
        require(position.collateral >= _collateralDelta, "positionCollateral must grate than _collateralDelta");

        uint256 collateral = position.collateral;
        // scrop variables to avoid stack too deep errors
        {
            // 减少储备金 包括个人仓位 和 池子
        uint256 reserveDelta = position.reserveAmount*(_sizeDelta)/(position.positionSize);
        position.reserveAmount = position.reserveAmount-(reserveDelta);
        _decreaseReservedAmount(_collateralToken, reserveDelta);
        }
        // 减少抵押 和 计算手续费 // usdOut是 减少抵押折算成美元的金额 usdOutAfterFee 是usdOut扣除手续费后的金额
        (uint256 usdOut, uint256 usdOutAfterFee) = _reduceCollateral(_account, _collateralToken, _indexToken, _collateralDelta, _sizeDelta, _isLong);

        if (position.positionSize != _sizeDelta) {
            //从cumulativeFundingRates mapping中取数
            position.entryFundingRate = cumulativeFundingRates[_collateralToken];
            //减少头寸
            position.positionSize -= _sizeDelta;
            // 需要保证降低后的头寸，依然要大于抵押
            _validatePosition(position.positionSize, position.collateral);
            // 校验流动性
            validateLiquidation(_account, _collateralToken, _indexToken, _isLong);

            if (_isLong) {
                // 多头，需要在GuaranteedUsd 中增加抵押数据
                _increaseGuaranteedUsd(_collateralToken, collateral-(position.collateral));
                // 同时，再减去 需要降低的头寸
                _decreaseGuaranteedUsd(_collateralToken, _sizeDelta);
            }

            uint256 price = _isLong ? getMinPrice(_indexToken) : getMaxPrice(_indexToken);
            emit DecreasePosition(key, _account, _collateralToken, _indexToken, _collateralDelta, _sizeDelta, _isLong, price, usdOut-(usdOutAfterFee));
            emit UpdatePosition(key, position.positionSize, position.collateral, position.averagePrice, position.entryFundingRate, position.reserveAmount, price);
        } else {
            if (_isLong) {
                // 先增加抵押，在再减去 需要降低的头寸
                _increaseGuaranteedUsd(_collateralToken, collateral);
                _decreaseGuaranteedUsd(_collateralToken, _sizeDelta);
            }

            uint256 price = _isLong ? getMinPrice(_indexToken) : getMaxPrice(_indexToken);
            emit DecreasePosition(key, _account, _collateralToken, _indexToken, _collateralDelta, _sizeDelta, _isLong, price, usdOut-(usdOutAfterFee));
            emit ClosePosition(key, position.positionSize, position.collateral, position.averagePrice, position.entryFundingRate);
            // 删除仓位
            delete positions[key];
        }

        if (!_isLong) {
            // 减少全局空头头寸大小
            _decreaseGlobalShortSize(_indexToken, _sizeDelta);
        }

        if (usdOut > 0) {
            if (_isLong) {
                // 如果是多头，需要降低池子中的数量，根据usdOut计算出最小的份额数量
                _decreasePoolAmount(_collateralToken, usdToTokenMin(_collateralToken, usdOut));
            }
            // 计算出需要转移出去的多少token（根据扣除手续费后的数量进行计算）
            uint256 amountOutAfterFees = usdToTokenMin(_collateralToken, usdOutAfterFee);
            _transferOut(_collateralToken, amountOutAfterFees, _receiver);
            return amountOutAfterFees;
        }

        return 0;
    }

    function _increaseReservedAmount(address _token, uint256 _amount) private {
        reservedAmounts[_token] += _amount;
        require(reservedAmounts[_token] <= poolAmounts[_token],"the reserve amount must less or equal than pool amount");
        emit IncreaseReservedAmount(_token, _amount);
    }

    function _decreaseReservedAmount(address _token, uint256 _amount) private {
        reservedAmounts[_token] -= _amount;
        emit DecreaseReservedAmount(_token, _amount);
    }

    function _increaseGuaranteedUsd(address _token, uint256 _amount) private {
        guaranteedUsds[_token] += _amount;
        emit IncreaseGuaranteedUsds(_token, _amount);
    }

    function _decreaseGuaranteedUsd(address _token, uint256 _amount) private {
        guaranteedUsds[_token] -= _amount;
        emit DecreaseGuaranteedUsds(_token, _amount);
    }

     function _increasePoolAmount(address _token, uint256 _amount) private {
        poolAmounts[_token] += _amount;
        emit IncreasePoolAmount(_token,_amount);
     }

     function _decreasePoolAmount(address _token, uint256 _amount) private {
        poolAmounts[_token] -= _amount;
        emit DecreasePoolAmount(_token,_amount);
     }

    function _increaseGlobalShortSize(address _token, uint256 _amount) private {
        globalShortSizes[_token] += _amount;
        emit IncreaseGlobalShortSize(_token,_amount);
    }

    function _decreaseGlobalShortSize(address _token, uint256 _amount) private {
        globalShortSizes[_token] -= _amount;
        emit DecreaseGlobalShortSize(_token,_amount);
    }


    function getPositionFee(uint256 _sizeDelta) internal view returns (uint256) {
        if (_sizeDelta == 0) { return 0; }
        uint256 afterFeeUsd = _sizeDelta*(BASIS_POINTS_DIVISOR-(marginFeeBasisPoints))/(BASIS_POINTS_DIVISOR);
        return _sizeDelta-afterFeeUsd;
    }

    function getFundingFee(address _collateralToken, uint256 _positionSize, uint256 _entryFundingRate) internal view returns (uint256) {
         if (_positionSize == 0) { return 0; }

        uint256 fundingRate = cumulativeFundingRates[_collateralToken]-(_entryFundingRate);
        if (fundingRate == 0) { return 0; }

        return _positionSize*(fundingRate)/(FUNDING_RATE_PRECISION);
    }

    function tokenToUsdMin(address _token, uint256 amount) internal view returns (uint256){
        if(amount == 0){
            return 0;
        }
        uint256 price = getMinPrice(_token);
        uint256 decimal = tokenDecimal[_token];
        return price * amount / (10 ** decimal);
    }

    function usdToTokenMin(address _token, uint256 _usdAmount) internal view returns(uint256){
        if(_usdAmount == 0){
            return 0;
        }
        uint256 price = getMaxPrice(_token);
        uint256 decimal = tokenDecimal[_token];
        return _usdAmount * (10 ** decimal) / price;
    }

    function usdToTokenMax(address _token, uint256 _usdAmount) internal view returns (uint256){
        if(_usdAmount==0){
            return 0;
        }
        uint256 price = getMinPrice(_token);
        uint256 decimal = tokenDecimal[_token];
        return _usdAmount * (10 ** decimal) / price;
    }


    function updateCumulativeFundingRate(address _collateralToken) internal {
        require(fundingInterval > 0, "fundingInterval did't init");
        if (!shouldUpdate) {
            return;
        }
        // 初始化lastFundingTimes
        if (lastFundingTimes[_collateralToken] == 0) {
            lastFundingTimes[_collateralToken] = block.timestamp/fundingInterval*fundingInterval;
            return;
        }
        // 检查是否到了下一资金间隔
        if (lastFundingTimes[_collateralToken] +fundingInterval  > block.timestamp) {
            return;
        }
        // 获取下一个资金利率fundingRate
        uint256 fundingRate = getNextFundingRate(_collateralToken);
        // 增加指定token的资金利率
        cumulativeFundingRates[_collateralToken] = cumulativeFundingRates[_collateralToken]+fundingRate;
        // 重新设置lastFundingTimes
        lastFundingTimes[_collateralToken] = block.timestamp/(fundingInterval)*(fundingInterval);

        emit UpdateFundingRate(_collateralToken, cumulativeFundingRates[_collateralToken]);
    }


    function getNextFundingRate(address _token) internal view returns (uint256){
         if (lastFundingTimes[_token]+fundingInterval > block.timestamp) { return 0; }

        uint256 intervals = (block.timestamp-lastFundingTimes[_token])/(fundingInterval);
        uint256 poolAmount = poolAmounts[_token];
        if (poolAmount == 0) { return 0; }
        // 判断是用稳定币的利率因子、资金利率因子
        uint256 _fundingRateFactor = stableTokens[_token] ? stableFundingRateFactor : fundingRateFactor;
        // 资金利率因子×预留金额×间隔数/池子资金
        return _fundingRateFactor*(reservedAmounts[_token])*(intervals)/(poolAmount);
    }

    function getPositionKey(address _account, address _collateralToken,address  _indexToken,bool _isLong) internal pure returns (bytes32){
        return keccak256(abi.encodePacked(_account,_collateralToken,_indexToken,_isLong));
    }

    //多头 nextSize * nextPrice / nextSize + 盈利  空头 nextSize * nextPrice / nextSize - 盈利
    function getNextAveragePrice(address _indexToken, uint256 _positionSize, uint256 _averagePrice, bool _isLong, uint256 _price, uint256 _sizeDelta, uint256 _lastUpdateTime) internal view returns (uint256){
        (bool hasProfit, uint256 delta) = getDelta(_indexToken, _positionSize, _averagePrice, _isLong, _lastUpdateTime);
        uint256 diverse;
        uint256 nextSize = _positionSize + _sizeDelta;
        if(_isLong){
            diverse = hasProfit ? nextSize + delta : nextSize-delta;
        }else{
            diverse = hasProfit ? nextSize - delta : nextSize+delta;
        }

        return _price * nextSize / diverse;
    }

    /**
     * 判断是否盈利
     */
    function getDelta(address _indexToken, uint256 _positionSize, uint256 _averagePrice, bool _isLong, uint256 _lastUpdateTime) internal view returns (bool,uint256) {
         require(_averagePrice > 0, "averagePrice must great than 0");
        // 单价获取  多头获取最低价  空头获取最高价
        uint256 price = _isLong ? getMinPrice(_indexToken) : getMaxPrice(_indexToken);
        // 获取平均价格和单价的价差
        uint256 priceDelta = _averagePrice > price ? _averagePrice-price : price-_averagePrice;
        // 计算盈亏金额
        uint256 delta = _positionSize*priceDelta/_averagePrice;

        bool hasProfit;

        if (_isLong) {  // 标记是否盈利
            hasProfit = price > _averagePrice;
        } else {
            hasProfit = _averagePrice > price;
        }

        // if the minProfitTime has passed then there will be no min profit threshold
        // the min profit threshold helps to prevent front-running issues
        // 这里应用了一个最小利润阈值（min profit threshold），以防止抢先交易（front-running）问题
        uint256 minBps = block.timestamp > _lastUpdateTime+(minProfitTime) ? 0 : minProfitBasisPoints[_indexToken];
        if (hasProfit && delta*(BASIS_POINTS_DIVISOR) <= _positionSize*(minBps)) {
            delta = 0;
        }

        return (hasProfit, delta);
    }


    function validateLiquidation(address _account, address _collateralToken, address _indexToken, bool _isLong) internal view returns (uint256,uint256){
        Position storage position = positions[getPositionKey(_account, _collateralToken, _indexToken, _isLong)];

        (bool hasProfit, uint256 delta) = getDelta(_indexToken, position.positionSize, position.averagePrice, _isLong, position.lastUpdateTime);
        // 计算保证金费用
        uint256 marginFees = getFundingFee(_collateralToken, position.positionSize, position.entryFundingRate);
        // 计算融资费用 / 持仓费用
        marginFees = marginFees+(getPositionFee(position.positionSize));

        if (!hasProfit && position.collateral < delta) {
            revert("losses exceed collateral");
        }

        // 检查是否亏损超过抵押品
        uint256 remainingCollateral = position.collateral;
        if (!hasProfit) {
            remainingCollateral = position.collateral-(delta);
        }
        // 计算剩余抵押品是否足够支付持仓费用
        if (remainingCollateral < marginFees) {
            revert("fees exceed collateral");
            
        }

        // 计算剩余抵押品是否足够支付清算费用
        if (remainingCollateral < marginFees+(liquidationFeeUsd)) {
            revert("liquidation fees exceed collateral");
            
        }

        // 检查是否超过了最大杠杆
        if (remainingCollateral*(maxLeverage) < position.positionSize*(BASIS_POINTS_DIVISOR)) {
            revert("Vault: maxLeverage exceeded");
        }

        return (0, marginFees);
    }


   function getNextGlobalShortAveragePrice(address _indexToken, uint256 _nextPrice, uint256 _sizeDelta) internal view returns(uint256) {
        uint256 size = globalShortSizes[_indexToken];
        uint256 averagePrice = globalShortAveragePrices[_indexToken];
        uint256 priceDelta = averagePrice > _nextPrice ? averagePrice-(_nextPrice) : _nextPrice-(averagePrice);
        uint256 delta = size*(priceDelta)/(averagePrice);
        bool hasProfit = averagePrice > _nextPrice;

        uint256 nextSize = size*(_sizeDelta);
        uint256 divisor = hasProfit ? nextSize-(delta) : nextSize+(delta);

        return _nextPrice*(nextSize)/(divisor);
   }

   function _authorizeUpgrade(address newImplementation) internal override{

   }
 

}