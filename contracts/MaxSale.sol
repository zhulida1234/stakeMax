//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./IAdmin.sol";
import "./Admin.sol";
import "./IERC20.sol";
import "./IMaxStake.sol";
import "./IERC20Metadata.sol";

contract MaxSale is Admin {

    // Admin contract
    // 指明这个销售合约归属于哪个admin
    IAdmin public admin;
    IMaxStake public stakeContract;
    // Sale
    Sale sale;
    // // Registration
    Registration public registration;
    // Number of users participated in the sale
    uint256 public numberOfParticipants;
    // Mapping user to his participation
    mapping(address => Participation) public userToParticipation;
    // Mapping if user is registered or not
    mapping(address => bool) public isRegistered;
    // Mapping if user is participated or not
    mapping(address => bool) public isParticiparted;
    // Times when portions are getting unlocked
    uint256[] public vestingPortionsUnlockTime;
    //Percent of the participation user can withdraw
    uint256[] public vestingPercentPerPortion;
    //Precision for percent for portion vesting
    uint256 public portionVestingPrecision;
    // Max vesting time shift
    uint256 public maxVestingTimeShift;
    

    // Define the sale struct
    // 定义销售行为数据结构
    struct Sale {
        // Token being sold;
        // 需要销售的代币
        IERC20 token;
        // Is sale created
        // 是否已经创建
        bool isCreated;
        // Are earnings withdrawn
        // 是否已经赚了收益
        bool earningsWithdrawn;
        // Is leftover withdraw
        // 未卖出部分
        bool leftoverWithdrawn;
        // Have tokens been deposited
        // 是否已经保存了代币数量
        bool tokensDeposited;
        // Address of sale owner
        // 持有人
        address saleOwner;
        // Price of the token quoted in ETH
        // token 使用ETH的单价
        uint256 tokenPriceInETH;
        // Amount of tokens to sell
        // 需要销售的代币数量
        uint256 amountOfTokensToSell;
        // Total Token being sold
        // 已经销售出去的代币数量
        uint256 totalTokensSold;
        // Total ETH Raised
        // 已经出售代币得到的ETH总金额
        uint256 totalETHRaised;
        // Sale start time
        // 销售开始时间
        uint256 saleStart;
        // Sale end time
        // 销售结束时间
        uint256 saleEnd;
        // When tokens can be withdraw
        // 代币解锁时间,只有超过这个时间，才可以提取剩余的代币
        uint256 tokensUnlockTime;
        // 最多一次只能购买的数量
        uint256 maxParticipation;
    }

    // Participation structure
    struct Participation {
        uint256 amountBought;
        uint256 amountETHPaid;
        uint256 timeParticipated;
        bool[] isPortionWithdraw;
    }

    struct Registration {
        uint256 registrationTimeStarts;
        uint256 registrationTimeEnds;
        uint256 numberOfRegistrants;
    }

    // Events
    event TokensSold(address user, uint256 amount);
    event UserRegistered(address user);
    event TokenPriceSet(uint256 newPrice);
    event MaxParticipationSet(uint256 maxParticipation);
    event TokensWithdrawn(address user, uint256 amount);
    event SaleCreated(
        address saleOwner,
        uint256 tokenPriceInETH,
        uint256 amountOfTokensToSell,
        uint256 saleEnd
    );
    event StartTimeSet(uint256 startTime);
    event RegistrationTimeSet(
        uint256 registrationTimeStarts,
        uint256 registrationTimeEnds
    );

    constructor(address _admin, address _allocationStaking) {
        require(_allocationStaking != address(0));
        admin = IAdmin(_admin);
        stakeContract = IMaxStake(_allocationStaking);
        admins.push(_admin);
        isAdmin[_admin]=true;
    }

    modifier onlySaleOwner() {
        require(msg.sender == sale.saleOwner, "OblySaleOwner:: restricted");
        _;
    }

    // modifier onlyAdmin override {
    //     require(isAdmin[msg.sender], "Only admin can call.");
    //     _;
    // }

    // // Admin function to set sale parameters
    function setSaleParams(
        address _token,
        address _saleOwner,
        uint256 _tokenPriceInETH,
        uint256 _amountOfTokensToSell,
        uint256 _saleEnd,
        uint256 _tokenUnlockTime,
        uint256 _portionVestingPrecision,
        uint256 _maxParticipation
    ) external onlyAdmin{
        require(!sale.isCreated, "Sale is already created");
        require(_saleOwner != address(0), "Sale owner address can not be 0");

        require(_tokenPriceInETH > 0 && _amountOfTokensToSell > 0 && _saleEnd > block.timestamp && _tokenUnlockTime > block.timestamp && _maxParticipation > 0,"Invalid input");
        require(_portionVestingPrecision >= 100, "portionVestingPrecision at least 100");

        sale.token = IERC20(_token);
        sale.isCreated = true;
        sale.saleOwner = _saleOwner;
        sale.tokenPriceInETH = _tokenPriceInETH;
        sale.tokensUnlockTime = _tokenUnlockTime;
        sale.maxParticipation = _maxParticipation;
        sale.amountOfTokensToSell = _amountOfTokensToSell;
        sale.saleEnd = _saleEnd;

        // set portion vesting precision
        portionVestingPrecision = _portionVestingPrecision;

        // Emit event
        emit SaleCreated(sale.saleOwner,sale.tokenPriceInETH,sale.amountOfTokensToSell,sale.saleEnd);
    }

    // // set Vesting Params (maxVestingTimeShift, _percents, _maxVestingTimeShift)
    // // 设置归属参数
    function setVestingParams(
        uint256[] memory _unlockingTimes,
        uint256[] memory _percents,
        uint256 _maxVestingTimeShift
    ) external onlyAdmin {
        require(
            vestingPortionsUnlockTime.length == 0 &&
                vestingPercentPerPortion.length == 0
        );
        require(_unlockingTimes.length == _percents.length);
        require(
            portionVestingPrecision > 0,
            "Safeguard for making sure setSaleParams get first called."
        );
        require(_maxVestingTimeShift <= 30 days, "Maximal shift is 30 days.");

        maxVestingTimeShift = _maxVestingTimeShift;
        uint256 sum;

        for (uint256 i = 0; i < _unlockingTimes.length; i++) {
            vestingPortionsUnlockTime.push(_unlockingTimes[i]);
            vestingPercentPerPortion.push(_percents[i]);
            sum += _percents[i];
        }

        require(sum == portionVestingPrecision, "Percent distribution issue");
    }

    // // set ShiftTime for vestingPortionsUnlockTimes. It just can set once
    // // 动态调整代表的释放时间, 并且确保了只能被调整一次
    function shiftVestingUnlockingTimes(uint256 timeToShift)
        external
        onlyAdmin
    {
        require(
            timeToShift > 0 && timeToShift < maxVestingTimeShift,
            "Shift must be nonzero and smaller than maxVestingTimeShift"
        );
        // The Time once set, It can't be shift once more
        maxVestingTimeShift = 0;

        for (uint256 i = 0; i < vestingPortionsUnlockTime.length; ++i) {
            vestingPortionsUnlockTime[i] += timeToShift;
        }
    }

    // //  only can be set when initial contract creation has passed but having no token at that moment
    // //  只能在初始化已经结束，同时因为当时还没有合适的token下才能被设置 
    function setSaleToken(address _saleToken) external onlyAdmin{
        // TODO 增加校验
        sale.token = IERC20(_saleToken);
    }

    // Function to set registration period parameters
    // 设置注册时间参数, 注册时间必须大于等于当前时间，且必须小于销售结束时间。如果设置了销售开始时间，则注册时间必须在销售开始时间之前
    function setRegistrationParams(uint256 _registrationTimeStarts,uint256 _registrationTimeEnds) external onlyAdmin{
        require(sale.isCreated);
        // only can be set once
        require(registration.registrationTimeStarts == 0);
        require(_registrationTimeStarts >= block.timestamp && _registrationTimeEnds > _registrationTimeStarts);
        require(_registrationTimeEnds < sale.saleEnd);

        if(sale.saleStart > 0) {
            require(_registrationTimeEnds < sale.saleStart, "registrationTimeEnds must be less than sale.saleStart");
        }

        registration.registrationTimeStarts = _registrationTimeStarts;
        registration.registrationTimeEnds = _registrationTimeEnds;

        emit RegistrationTimeSet(_registrationTimeStarts, _registrationTimeEnds);

    }

    // set Sale Start Time
    // 设置销售开始时间
    function setSaleStart(uint256 startTime) external onlyAdmin{
        require(sale.isCreated, "sale is not created");
        require(sale.saleStart == 0, "saleStart is set already");
        require(startTime > registration.registrationTimeStarts, "start time should greater than registrationTimeEnds");
        require(startTime < sale.saleEnd, "start time should less than end time");

        sale.saleStart = startTime;
        emit StartTimeSet(startTime);
    }

    // registration for sale.
    // 注册销售人员
    function registerForSale(bytes memory signature, uint256 _pid) external {
        require(block.timestamp >= registration.registrationTimeStarts && block.timestamp <= registration.registrationTimeEnds, "registration gate is closed");
        // require(checkRegistrationSignation(signature, msg.sender),"Invalid signature");

        require(!isRegistered[msg.sender], "User can't be register twice");
        isRegistered[msg.sender] = true;

        stakeContract.setTokenUnlockTime(_pid,msg.sender,sale.saleEnd);

        registration.numberOfRegistrants++;

        emit UserRegistered(msg.sender);
    }

    function updateTokenPriceInETH(uint256 price) external onlyAdmin {
        require(price > 0, "price can't be 0");
        sale.tokenPriceInETH = price;
        emit TokenPriceSet(price);
    }

    // postpone the sale
    // 推迟销售开始时间
    function postponeSale(uint256 timeToShift) external onlyAdmin{
        require(block.timestamp < sale.saleStart, "sale already start");

        sale.saleStart += timeToShift;
        require(
            sale.saleStart + timeToShift < sale.saleEnd,
            "Start time can not be greater than end time."
        );

    }

    // extend registration period
    // 增加注册周期
    function extendRegisttrationPeriod(uint256 timeToAdd) external onlyAdmin {
        require(registration.registrationTimeEnds + timeToAdd < sale.saleStart,"Registration period over than saleStart" );

        registration.registrationTimeEnds += timeToAdd; 
    }

    // Admin function to set max participation before sale start
    function setCap(uint256 cap) external onlyAdmin {
        require(block.timestamp < sale.saleStart,"sale already start");
        require(cap > 0, "can't set max participation to 0");

        sale.maxParticipation = cap;
        emit MaxParticipationSet(sale.maxParticipation);
    }

    function depositTokens() external onlySaleOwner {
        require(!sale.tokensDeposited, "Deposit can be execute only once! ");

        sale.tokensDeposited = true;
        sale.token.transferFrom(msg.sender,address(this),sale.amountOfTokensToSell);
    }


    function participate(bytes memory signature,uint256 amount) external payable {
        require(amount <= sale.maxParticipation,"Overflow maximal participation for sale");
        require(isRegistered[msg.sender], "Not registered for this sale");
        // require(checkPartcipationSignature(signature,msg.sender,amount),"Invalid signature. Verification failed");
        require(!isParticiparted[msg.sender], "User can participate only once.");
        
        uint256 amountOfTokenBuying = msg.value * (10 ** IERC20Metadata(address(sale.token)).decimals()) / sale.tokenPriceInETH;
        // uint256 amountOfTokenBuying = 10;
        require(amountOfTokenBuying > 0, "Can't buy 0 tokens");
        require(amountOfTokenBuying <= amount,"Try to bug more than allowed.");

        sale.totalTokensSold += amountOfTokenBuying;
        sale.totalETHRaised += msg.value;

        bool[] memory _isPortionWithdrawn = new bool[](
            vestingPortionsUnlockTime.length
        );

        // create participation object
        Participation memory p = Participation({amountBought : amountOfTokenBuying,amountETHPaid : msg.value, timeParticipated :block.timestamp,isPortionWithdraw : _isPortionWithdrawn}); 
        // Add participation for user.
        userToParticipation[msg.sender] = p;
        // Mark user is participated
        isParticiparted[msg.sender] = true;
        // Increment number of participants in the Sale.
        numberOfParticipants++;

        emit TokensSold(msg.sender, amountOfTokenBuying);
    }

    
    function withdrawTokens(uint256 portionId) external {
        require(block.timestamp >= sale.tokensUnlockTime, "Tokens can not be withdrawn yet.");
        require(portionId < vestingPercentPerPortion.length, "Portion id out of range.");

        Participation storage p = userToParticipation[msg.sender];
        if(!p.isPortionWithdraw[portionId] && vestingPortionsUnlockTime[portionId] <= block.timestamp){
            p.isPortionWithdraw[portionId] = true;
            uint256 amountWithdrawing = p.amountBought*vestingPercentPerPortion[portionId]/portionVestingPrecision;

            if(amountWithdrawing > 0){
                sale.token.transfer(msg.sender, amountWithdrawing);
                emit TokensWithdrawn(msg.sender, amountWithdrawing);
            }
        } else {
            revert("Tokens already withdrawn or portiion not unlocked yet");
        }
    }

    function withdrawMultiplePortions(uint256 [] calldata portionIds) external {
        uint256 totalToWithdraw = 0;

        Participation storage p = userToParticipation[msg.sender];

        for(uint i=0; i< portionIds.length; i++){
            uint256 portionId = portionIds[i];
            require(portionId < vestingPercentPerPortion.length);

            if(!p.isPortionWithdraw[portionId] && vestingPortionsUnlockTime[portionId] <= block.timestamp) {
                p.isPortionWithdraw[portionId] = true;
                uint256 amountWithdrawing = p.amountBought * vestingPercentPerPortion[portionId] / portionVestingPrecision;
                totalToWithdraw += amountWithdrawing;
            }
        }

        if (totalToWithdraw > 0) {
            sale.token.transfer(msg.sender, totalToWithdraw);
            emit TokensWithdrawn(msg.sender, totalToWithdraw);
        }
    }

    // Internal function to handle safe transfer
    function safeTransferETH(address to, uint256 value) internal {
        (bool success,) = to.call{value : value}(new bytes(0));
        require(success);
    }

    /// Function to withdraw all the earnings and the leftover of the sale contract.
    function withdrawEarningsAndLeftover() external onlySaleOwner {
        withdrawEarningsInternal();
        withdrawLeftoverInternal();
    }

    // Function to withdraw only earnings
    function withdrawEarnings() external onlySaleOwner {
        withdrawEarningsInternal();
    }

    // Function to withdraw only leftover
    function withdrawLeftover() external onlySaleOwner {
        withdrawLeftoverInternal();
    }

    // function to withdraw earnings
    function withdrawEarningsInternal() internal {
        // Make sure sale ended
        require(block.timestamp >= sale.saleEnd, "sale is not ended yet.");

        // Make sure owner can't withdraw twice
        require(!sale.earningsWithdrawn, "owner can't withdraw earnings twice");
        sale.earningsWithdrawn = true;
        // Earnings amount of the owner in ETH
        uint256 totalProfit = sale.totalETHRaised;

        safeTransferETH(msg.sender, totalProfit);
    }

     // Function to withdraw leftover
    function withdrawLeftoverInternal() internal {
        // Make sure sale ended
        require(block.timestamp >= sale.saleEnd, "sale is not ended yet.");

        // Make sure owner can't withdraw twice
        require(!sale.leftoverWithdrawn, "owner can't withdraw leftover twice");
        sale.leftoverWithdrawn = true;

        // Amount of tokens which are not sold
        uint256 leftover = sale.amountOfTokensToSell-(sale.totalTokensSold);

        if (leftover > 0) {
            sale.token.transfer(msg.sender, leftover);
        }
    }

    /// @notice     Function to get number of registered users for sale
    function getNumberOfRegisteredUsers() external view returns (uint256) {
        return registration.numberOfRegistrants;
    }

    /// @notice     Function to get all info about vesting.
    function getVestingInfo()
    external
    view
    returns (uint256[] memory, uint256[] memory)
    {
        return (vestingPortionsUnlockTime, vestingPercentPerPortion);
    }

    // check the signature
    function checkRegistrationSignation(bytes memory signature,address user) internal view returns (bool) {
        bytes32 hash = keccak256(
            abi.encodePacked(user, address(this))
        );
        bytes32 messageHash = toEthSignedMessageHash(hash);

        return admin.isAdmin(recover(messageHash,signature));
    }

    function checkParticipationSignature(bytes memory signature,address user,uint256 amount) internal view returns (bool){
        return admin.isAdmin(getParticipationSigner(signature,user,amount));
    }

    function getParticipationSigner(bytes memory signature,address user,uint256 amount) internal view returns (address){
        bytes32 hash = keccak256(abi.encodePacked(user,amount,address(this)));
        bytes32 messageHash = toEthSignedMessageHash(hash);
        return recover(messageHash,signature);
    }

    function recover(bytes32 hash, bytes memory signature) internal pure returns (address) {
        if (signature.length == 65) {
            bytes32 r;
            bytes32 s;
            uint8 v;

            assembly {
                r := mload(add(signature, 0x20))
                s := mload(add(signature, 0x40))
                v := byte(0, mload(add(signature, 0x60)))
            }

            address signer = ecrecover(hash, v, r, s);
            if (signer == address(0)) {
                revert("invalid signature");
            }
            return signer;
        }else {
            revert("invalid signatrue length");
        }

    }

    //TODO remove this function to util 
    function toEthSignedMessageHash(bytes32 hash) internal pure returns (bytes32 message) {
        // 32 is the length in bytes of hash,
        // enforced by the type signature above
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, "\x19Ethereum Signed Message:\n32")
            mstore(0x1c, hash)
            message := keccak256(0x00, 0x3c)
        }
    }


    // Function to act as a fallback and handle receiving ETH.
    receive() external payable {}

    

}

