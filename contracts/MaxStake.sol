// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./interface/IERC20.sol";
import "./token/ERC20.sol";
import "./interface/IMaxStake.sol";
import "./utils/ReentrancyGuard.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract MaxStake is IMaxStake,ReentrancyGuard,Initializable,UUPSUpgradeable,AccessControlUpgradeable,PausableUpgradeable{
    //reward token
    //奖励代币
    IERC20 public ierc20B2;
    //interest token
    //利率代币
    IERC20 public interestToken;
    //initInterest
    //初始化利息
    uint256 public initInterest;
    // 活动开始时间
    uint256 public startTimeStamp;
    // 活动结束时间
    uint256 public endTimeStamp;

    // 每秒奖励的数量
    uint public rewardPerSecond;
     // 总分配的点数
    uint256 public totalAllocPoint;
    // 总的奖励金额
    uint256 public totalRewards;
    // 总的已支付出去的奖励
    uint256 public paidOut;
    // 拥有人
    address private _owner;
    // 用户在流动性池子里面的存款
    mapping(uint256 => mapping(address => User)) userInfo;

    // 借出利率
    uint256 lendingInterestRate;
    // 借入利率
    uint256 borrowingInterestRate;
    // 借出奖励的利率
    uint256 lendingRewardInterestRate;
    // 借入奖励的利率
    uint256 borrowingRewardInterestRate;
    // lockPeriod
    uint256 lockPeriod;
    // minLending Amount
    uint256 minLending;
    // collateraRate
    // 抵押率
    uint256 collateralRate;
    // 奖励token 抵押率
    uint256 collateralRewardRate;
    // 最小奖励抵押量
    uint256 mincollateral;

    // 暂停功能的状态
    bool public withdrawPaused;
    // 提取功能的状态
    bool public claimPaused;

    struct Pool {
        // 代币的Token地址
        address stTokenAddress;
        // 质押权重
        uint256 poolWeight;
        // 最后一次计算奖励时间
        uint256 lastRewardBlock;
        // 每个代币奖励质押B2份额
        uint256 accB2PerST;
        // 池子中总的代币数量
        uint256 stTokenAmount;
        // 最小质押代币数量
        uint256 minDepositAmount;
        // 最小解除质押代币数量
        uint256 unstakeLockedBlocks;
        // 总借出代币数量
        uint256 lendingAmount;
        // 总借入代币数量
        uint256 borrowingAmount;
        // 总借出奖励数量
        uint256 lendingRewardAmount;
        // 总借入奖励数量
        uint256 borrowingRewardAmount;
    }

    struct LandingInfo {
        uint256 landingRewardAmount;
        //landingAmount
        uint256 landingAmount;
        //landingTime
        uint256 landingLastTime;
        //accumulateInterest
        uint256 accumulateInterest;
        //accumulateRewardInterest
        uint256 accumulateRewardInterest;
    }

    mapping(address => mapping(address => LandingInfo)) landingValues;

    struct BorrowingInfo {
        //collateralReward
        uint256 collateralReward;
        //borrowingAmount
        uint256 borrowingAmount;
        //borrowTime
        uint256 borrowLastTime;
        //accumulateInterest
        uint256 accumulateInterest;
    }

    mapping(address => mapping(address => BorrowingInfo)) borrowingValues;

    Pool[] public pools;

    struct User {
        // 用户质押的代币数量
        uint256 stAmount;
        // 用户已经分配的奖励代币数量
        uint256 finishedB2;
        // 用户待分配的奖励代币数量
        uint256 pendingB2;
        // tokenUnlockTime
        uint256 tokensUnlockTime;
        // registered sale users
        address [] salesRegistered;
    }
    // 质押事件
    event Deposit(uint256 _pid,uint256 amount);
    // 解质押事件
    event Withdraw(uint256 _pid,uint256 amount);
    // 奖励事件
    event Reward(uint256 _pid);
    // 取款暂停
    event WithdrawPaused();
    // 领取奖励暂停
    event ClaimPaused();
    // 取款恢复
    event WithdrawUnPaused();
    // 领奖恢复
    event ClaimUnPaused();
    // 更新对应的流动池
    event UpdatePool(uint256 idx, uint256 lastRewardBlock, uint256 reward);
    // 存款借出
    event DepositLend(uint256 _pid,uint _amount);
    // 提取借出
    event WithdrawLend(uint256 _pid,uint _amount);
    // 领取奖励借出
    event ClaimLend(uint256 _pid);
    // 存款借入
    event DepositBorrow(uint256 _pid,uint _amount);
    // 提取并借入
    event WithdrawBorrow(uint256 _pid,uint _amount);
    // 抵押奖励借入
    event ClaimBorrow(uint256 _pid);
    // 赎回
    event Redeem(uint256 _pid,uint256 borrowAmt,uint256 collateralReward,uint256 accumulateInterest,address receiver);
    // 结算
    event Settle(uint256 _pid,uint256 landingAmount,uint256 landingRewardAmount,uint256 totalInterest,address receiver);

    // 构造函数，初始化奖励代币数量 
    function initialize(address _b2stAddress, uint256 _rewardPerSecond,uint256 _startTimeStamp,uint256 _endTimeStamp) external initializer {
        require(_startTimeStamp < _endTimeStamp,"Invalid time");
        require(_endTimeStamp > block.timestamp, "Invalid end time");
        ierc20B2 = IERC20(_b2stAddress);
        rewardPerSecond = _rewardPerSecond;
        startTimeStamp = _startTimeStamp;
        endTimeStamp = _endTimeStamp;
        _owner = msg.sender;

        __UUPSUpgradeable_init();
    }

    // 校验withdraw没有暂停
    modifier withdrawUnPaused () {
        require(!withdrawPaused,"withdraw is Paused");
        _;
    }

    // 校验claim没有暂停
    modifier claimUnPaused () {
        require(!claimPaused, "claim is Paused");
        _;
    }

    // 校验是否属于所有人
    modifier onlyOwner() {
        require(_owner == msg.sender,"Invalid Operator");
        _;
    }

    // 校验是否可以出借
    modifier validateLend(uint256 _amount) {
        require(address(interestToken) != address(0),"the interestToken may not init");
        require(_amount > 0, "lending amount can't be zero");
        require(lendingInterestRate > 0,"the lendingInterestRate may not init");
        require(_amount >= minLending, "lending Amount must great than minLending");
        _;
    }

    // 校验接款参数
    modifier validateBorrow(uint256 _amount) {
        require(address(interestToken) != address(0),"the interestToken may not init");
        require(_amount > 0, "lending amount can't be zero");
        require(borrowingInterestRate > 0,"the lendingInterestRate may not init");
        _;
    }

    // 暂停取款
    function pauseWithdraw () external onlyOwner withdrawUnPaused {
        withdrawPaused = true;

        emit WithdrawPaused();
    }

    // 暂停领取奖励
    function pauseClaim () external onlyOwner claimUnPaused {
        claimPaused = true;

        emit ClaimPaused();
    }

    function unPauseWithdraw () external onlyOwner {
        require(withdrawPaused, "withdraw is unPaused");
        withdrawPaused = false;

        emit WithdrawUnPaused();
    }

    function unPauseClaim () external onlyOwner {
        require(claimPaused, "claim is unPaused");
        claimPaused = false;

        emit ClaimUnPaused();
    }

    // 为池子注入B2资金(作为整体奖励)
    function fund(uint256 _amount) external onlyOwner {
        require(block.timestamp < endTimeStamp, "Time is too late");
        totalRewards += _amount;
        endTimeStamp += _amount/rewardPerSecond;

        ierc20B2.transferFrom(msg.sender, address(this), _amount);
    }

    // 为合约增加流动性提供者
    function add(address _tokenAddr,bool _withUpdate,uint256 _poolWeight,uint256 _minDepositAmount,uint256 _unstakeLockedBlocks) external onlyOwner {
        if(_withUpdate){
            //更新所有的流动性池子
            massUpdatePools();
        }
        uint256 _lastRewardBlock = block.timestamp > startTimeStamp ? block.timestamp : startTimeStamp;
        // 往流动性池子中增加一个流动性pool
        pools.push(Pool({stTokenAddress:_tokenAddr,poolWeight:_poolWeight,lastRewardBlock:_lastRewardBlock,accB2PerST:0,stTokenAmount:0,minDepositAmount:_minDepositAmount,unstakeLockedBlocks:_unstakeLockedBlocks,lendingAmount:0,borrowingAmount:0,lendingRewardAmount:0,borrowingRewardAmount:0}));
        // 总的分配点数增加
        totalAllocPoint += _poolWeight;

    }

    // 重新设置流动性提供者的分配点数
    function set(uint256 _pid,uint256 _poolWeight,bool _withUpdate) external onlyOwner {
        if(_withUpdate){
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint-pools[_pid].poolWeight+_poolWeight;
        pools[_pid].poolWeight = _poolWeight;
    
    }

    // setting interest
    // 设置借出利率 和 借入利率
    function setInterestRate(uint256 _lendingInterestRate,uint256 _borrowingInterestRate,uint256 _lendingRewardInterestRate,uint256 _borrowingRewardInterestRate) external onlyOwner{
        require(_lendingInterestRate < _borrowingInterestRate,"the borrowingInterest must great than lendingInterest");
        require(_lendingInterestRate > 0 && _borrowingInterestRate > 0,"the interest must great than 0");
        require(lendingInterestRate == 0 && borrowingInterestRate ==0, "the interest can be set just once");

        lendingInterestRate = _lendingInterestRate;
        borrowingInterestRate = _borrowingInterestRate;
        lendingRewardInterestRate = _lendingRewardInterestRate;
        borrowingRewardInterestRate = _borrowingRewardInterestRate;
    }

    // seting interestToken,lockPeriod and initInterest
    // 设置利率token，锁定期间，注入利息
    function setInterestParams(address _interestToken,uint256 _lockPeriod,uint256 _initInterest,uint256 _minLanding, uint256 _collateralRate,uint256 _collateralRewardRate, uint256 _mincollateral) external onlyOwner{
        require(_interestToken!=address(0),"invalid Token address");
        require(address(interestToken)==address(0),"the interestToken have alread seted");
        require(_lockPeriod>0,"lock period must great than 0");
        require(_initInterest>0,"initInterest must great than 0");

        interestToken = IERC20(_interestToken);
        lockPeriod = _lockPeriod;
        initInterest = _initInterest;
        minLending = _minLanding;
        collateralRate = _collateralRate;
        collateralRewardRate = _collateralRewardRate;
        mincollateral = _mincollateral;


    }

    // 更新所有的流动性池子
    function massUpdatePools() internal {
        for(uint i=0;i<pools.length;++i){
            updatePool(i);
        }
    }


    // 单个更新流动性池子
    function updatePool(uint256 idx) internal {
        Pool storage pool = pools[idx];
        uint256 lastTime = block.timestamp < endTimeStamp ? block.timestamp : endTimeStamp;
        if(lastTime <= pool.lastRewardBlock){
            return;
        }
        uint256 totalSupply = pool.stTokenAmount;
        if(totalSupply == 0){
            pool.lastRewardBlock = lastTime;
            return;
        }
        // 计算持续时间
        uint256 effectTime = lastTime - pool.lastRewardBlock;
        uint256 accB2PerST = pool.accB2PerST;

        uint256 reward = rewardPerSecond*(effectTime)*(pool.poolWeight)/(totalAllocPoint);
        accB2PerST = accB2PerST+(reward*(1e36)/(totalSupply));

        pool.accB2PerST = accB2PerST;
        pool.lastRewardBlock = block.timestamp;
        emit UpdatePool(idx, pool.lastRewardBlock, reward);
    }

    // 质押
    function deposit(uint256 _pid,uint256 amount) external claimUnPaused{
        require(block.timestamp < endTimeStamp, "time is over");
        Pool storage pool = pools[_pid];
        require(amount >= pool.minDepositAmount, "amount less than limit");

        User storage user = userInfo[_pid][msg.sender];

        updatePool(_pid);
        if(user.stAmount > 0){
            // 先取出奖励池子里面的奖励，给到质押者
            uint256 reward = pending(_pid, msg.sender);
            user.finishedB2 += reward;
            user.pendingB2 = 0;
            ierc20B2.transfer(msg.sender,reward);
        }else{
            user.pendingB2 = user.stAmount*(pool.accB2PerST)/(1e36)-user.finishedB2;
        }

        user.stAmount = user.stAmount + amount;
        pool.stTokenAmount += amount; 

        IERC20(pool.stTokenAddress).transferFrom(msg.sender,address(this),amount);

        emit Deposit(_pid,amount);
    }

    // 解除质押
    function withdraw(uint256 _pid, uint256 _amount) external withdrawUnPaused{
        User storage user = userInfo[_pid][msg.sender];
        require(_amount > 0, "Invalid Amount");
        require(user.stAmount >= _amount, "the balance less than amount");
        Pool storage pool = pools[_pid];
        
        updatePool(_pid);
        // 先取出奖励池子里面的奖励，给到质押者
        uint256 reward = pending(_pid, msg.sender);
        user.finishedB2 += reward;
        user.pendingB2 = 0;
        ierc20B2.transfer(msg.sender,reward);
        

        user.stAmount = user.stAmount - _amount;
        pool.stTokenAmount -= _amount; 

        IERC20(pool.stTokenAddress).transfer(msg.sender,_amount);

        emit Withdraw(_pid, _amount);
    }

    // 获取奖励
    function reward(uint256 _pid) external claimUnPaused{
        User storage user = userInfo[_pid][msg.sender];

        uint256 reward = pending(_pid, msg.sender);
        user.finishedB2 += reward;
        user.pendingB2 = 0;
        ierc20B2.transfer(msg.sender,reward);

        emit Reward(_pid);
    }


    //查看指定用户,在指定池子里面的待领取代币奖励
    function pending(uint _pid,address _user) internal view returns (uint256){
        User storage user = userInfo[_pid][_user];
        Pool storage pool = pools[_pid];
        uint256 accB2PerST = pool.accB2PerST;
        uint256 totalSupply = pool.stTokenAmount;
        if(block.timestamp > pool.lastRewardBlock && totalSupply > 0){
            uint256 lastTime = block.timestamp < endTimeStamp ? block.timestamp : endTimeStamp;
            uint256 compareLastRewardTime = pool.lastRewardBlock < endTimeStamp ? pool.lastRewardBlock : endTimeStamp;
            uint256 effectTime = lastTime - compareLastRewardTime;
            uint256 reward = rewardPerSecond*effectTime*pool.poolWeight/(totalAllocPoint);
            accB2PerST = accB2PerST+(reward*(1e36)/(totalSupply));
        }

        return user.stAmount*(accB2PerST)/(1e36)-(user.finishedB2);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner{

    }

    function setTokenUnlockTime(uint256 _pid,address _user,uint256 saleEndTime) external {
        User storage user = userInfo[_pid][_user];
        require(user.tokensUnlockTime <= block.timestamp);
        user.tokensUnlockTime = saleEndTime;
        user.salesRegistered.push(msg.sender);
    }

    // the use can depositLending the token to this contract. to earn the interest
    // 
    function depositLend(uint256 _pid,uint256 _amount) external nonReentrant validateLend(_amount){
        Pool storage pool = pools[_pid];

        LandingInfo storage landingInfo = landingValues[pool.stTokenAddress][msg.sender];
        // 如果之前已经有出借的记录,则先计算利息
        if(landingInfo.landingAmount > 0){
            uint256 timePeriod = block.timestamp - landingInfo.landingLastTime;
            landingInfo.accumulateInterest +=landingInfo.landingAmount * timePeriod * lendingInterestRate * 1e36/(365 * 24 * 3600);
        }

        landingInfo.landingAmount += _amount;
        landingInfo.landingLastTime = block.timestamp;

        pool.lendingAmount += _amount; 

        IERC20(pool.stTokenAddress).transferFrom(msg.sender,address(this),_amount);
        // 发送事件
        emit DepositLend(_pid,_amount);
    }

    /**
     * 
     * 执行逻辑,因为是从质押池子中取出来的token，借给合约。而本身，对应的token其实就是在合约上，
     * 因此，先计算质押奖励，发送给用户
     * 其次, 更新个人用户 和 池子中的质押代币数量
     * 再次, 判断是否需要计算上一周期内的利息额
     * 更新借款信息的借款金额，操作时间
     * 考虑到，token的最终归属没有变,transferFrom这个方法不需要调用
     */
    function withdrawLend(uint256 _pid,uint256 _amount) external nonReentrant withdrawUnPaused validateLend(_amount){
        User storage user = userInfo[_pid][msg.sender];
        require(user.stAmount >= _amount, "the balance less than amount");

        Pool storage pool = pools[_pid];
        updatePool(_pid);
        // 先取出奖励池子里面的奖励，给到质押者
        uint256 reward = pending(_pid, msg.sender);
        user.finishedB2 += reward;
        user.pendingB2 = 0;
        ierc20B2.transfer(msg.sender,reward);
        // 然后将 取出来的金额借给合约，开始计算利息
        user.stAmount = user.stAmount - _amount;
        pool.stTokenAmount -= _amount; 

        LandingInfo storage landingInfo = landingValues[pool.stTokenAddress][msg.sender];
        if(landingInfo.landingAmount > 0){
            uint256 timePeriod = block.timestamp - landingInfo.landingLastTime;
            landingInfo.accumulateInterest +=landingInfo.landingAmount * timePeriod * lendingInterestRate * 1e36/(365 * 24 * 3600);
        }

        landingInfo.landingAmount += _amount;
        landingInfo.landingLastTime = block.timestamp;

        pool.lendingAmount += _amount; 
        // 发送事件
        emit WithdrawLend(_pid,_amount);
    }

    /**
     * 借出奖励,获取奖励的利息
     * 逻辑大致和提取奖励逻辑差不多，最后同样是不调用transfer方法，只是将最终的数据进行调整
     * @param _pid 池id
     */
    function claimLend(uint256 _pid) external nonReentrant claimUnPaused{
        Pool storage pool = pools[_pid];
        User storage user = userInfo[_pid][msg.sender];

        uint256 reward = pending(_pid, msg.sender);
        user.finishedB2 += reward;
        user.pendingB2 = 0;

        LandingInfo storage landingInfo = landingValues[pool.stTokenAddress][msg.sender];
        if(landingInfo.landingRewardAmount > 0){
            uint256 timePeriod = block.timestamp - landingInfo.landingLastTime;
            landingInfo.accumulateRewardInterest +=landingInfo.landingRewardAmount * timePeriod * lendingRewardInterestRate * 1e36/(365 * 24 * 3600);
        }

        landingInfo.landingRewardAmount += reward;
        landingInfo.landingLastTime = block.timestamp;
        pool.lendingRewardAmount += reward;
        // 发送事件
        emit ClaimLend(_pid);
    }

    function depositBorrow(uint256 _pid,uint256 _amount) external nonReentrant validateBorrow(_amount){
        Pool storage pool = pools[_pid];

        uint256 canBorrowAmt = _getCanBorrowAmt(_pid);
        BorrowingInfo storage borrowingInfo = borrowingValues[pool.stTokenAddress][msg.sender];

        require(canBorrowAmt-borrowingInfo.borrowingAmount > _amount,"the borrowAmt overflow");
        require(pool.lendingAmount-pool.borrowingAmount > _amount, "total borrow amount must less than total lending");

        // 如果之前已经有出借的记录,则先计算利息
        if(borrowingInfo.borrowingAmount > 0){
            uint256 timePeriod = block.timestamp - borrowingInfo.borrowLastTime;
            borrowingInfo.accumulateInterest +=borrowingInfo.borrowingAmount * timePeriod * borrowingInterestRate * 1e36/(365 * 24 * 3600);
        }

        borrowingInfo.borrowingAmount += _amount;
        borrowingInfo.borrowLastTime = block.timestamp;

        pool.borrowingAmount += _amount; 

        IERC20(pool.stTokenAddress).transfer(msg.sender,_amount);
        // 发送事件
        emit DepositBorrow(_pid,_amount);
    }

    /***
     * 如果之前已经有过了借款，提取本金后可以借款的金额 > 已借款金额
     * 则本次借款数量 可以借款的最大金额 - 已借款金额
     * 如果没有借款
     */
    function withdrawBorrow(uint256 _pid,uint256 _amount) external nonReentrant withdrawUnPaused validateBorrow(_amount){
        User storage user = userInfo[_pid][msg.sender];
        require(user.stAmount >= _amount, "the balance less than amount");
        uint256 canBorrowAmt=_getCanBorrowAmt(_pid);
        Pool storage pool = pools[_pid];
        BorrowingInfo storage borrowingInfo = borrowingValues[pool.stTokenAddress][msg.sender];
        require(canBorrowAmt-borrowingInfo.borrowingAmount > _amount,"the borrow amount overflow than limit");
        
        updatePool(_pid);
        // 先取出奖励池子里面的奖励，给到质押者
        uint256 reward = pending(_pid, msg.sender);
        user.finishedB2 += reward;
        user.pendingB2 = 0;
        ierc20B2.transfer(msg.sender,reward);

        user.stAmount = user.stAmount - _amount;
        pool.stTokenAmount -= _amount; 
        // 然后将 取出来的金额借给合约，开始计算利息
        if(borrowingInfo.borrowingAmount > 0){
            uint256 timePeriod = block.timestamp - borrowingInfo.borrowLastTime;
            borrowingInfo.accumulateInterest +=borrowingInfo.borrowingAmount * timePeriod * borrowingInterestRate * 1e36/(365 * 24 * 3600);
        }
        uint256 reallyBorrowAmt = user.stAmount * collateralRate /100 - borrowingInfo.borrowingAmount;
        borrowingInfo.borrowingAmount += reallyBorrowAmt;
        borrowingInfo.borrowLastTime = block.timestamp;

        pool.borrowingAmount += reallyBorrowAmt;
        
        uint256 reallySendAmt = _amount + reallyBorrowAmt;
        IERC20(pool.stTokenAddress).transfer(msg.sender,reallySendAmt);

        emit WithdrawBorrow(_pid,_amount);
    }

    /**
     * 
     */
    function claimBorrow(uint256 _pid) external nonReentrant claimUnPaused {
        require(address(interestToken) != address(0),"the interestToken may not init");
        require(borrowingInterestRate > 0,"the lendingInterestRate may not init");

        User storage user = userInfo[_pid][msg.sender];

        Pool storage pool = pools[_pid];
        BorrowingInfo storage borrowingInfo = borrowingValues[pool.stTokenAddress][msg.sender];
        uint256 reward = pending(_pid, msg.sender);
        require(reward > mincollateral, "the reward must great than mincollateral");
        if(borrowingInfo.borrowingAmount > 0){
            uint256 timePeriod = block.timestamp - borrowingInfo.borrowLastTime;
            borrowingInfo.accumulateInterest +=borrowingInfo.borrowingAmount * timePeriod * borrowingInterestRate * 1e36/(365 * 24 * 3600);
        }

        
        user.finishedB2 += reward;
        user.pendingB2 = 0;

        uint256 canborrowAmt=_calculateRewardCollateral(reward);

        borrowingInfo.borrowingAmount += canborrowAmt;
        borrowingInfo.collateralReward += reward;
        borrowingInfo.borrowLastTime = block.timestamp;

        
        pool.borrowingRewardAmount += reward;

        IERC20(pool.stTokenAddress).transfer(msg.sender,canborrowAmt);

        emit ClaimBorrow(_pid);
    }
    /**
     * 计算能够借款多少
     */
    function _getCanBorrowAmt(uint256 _pid) private view returns (uint256){
        User storage user = userInfo[_pid][msg.sender];
        uint256 totalCanBorrowAmt = user.stAmount * collateralRate /100;

        return totalCanBorrowAmt;
    }

    /**
     * 计算奖励能抵押多少的token,因为奖励token的数量较大，
     * 因此计算的时候，要除以一个较大的数，这里为10的6次方
     */
    function _calculateRewardCollateral(uint256 _reward) private view returns (uint256){
        uint256 collateralAmt = _reward * collateralRewardRate/1e6;
        return collateralAmt;
    }

    /**
     * 偿还所有借到的token(包括通过抵押的奖励token借到的)，并支付指定的利息
     * 需要将抵押的奖励token退回到自己的账户上
     */
    function redeem(uint256 _pid) external nonReentrant{
        Pool storage pool = pools[_pid];
        BorrowingInfo storage borrowingInfo = borrowingValues[pool.stTokenAddress][msg.sender];
        // 先进行利息的计算
        uint256 timePeriod = block.timestamp - borrowingInfo.borrowLastTime;
        borrowingInfo.accumulateInterest +=borrowingInfo.borrowingAmount * timePeriod * borrowingInterestRate * 1e36/(365 * 24 * 3600);

        pool.borrowingAmount -= borrowingInfo.borrowingAmount;

        uint256 borrowAmt = borrowingInfo.borrowingAmount;
        uint256 collateralReward = borrowingInfo.collateralReward;
        uint256 accumulateInterest =  borrowingInfo.accumulateInterest;

        interestToken.transfer(address(this),borrowingInfo.accumulateInterest);
        IERC20(pool.stTokenAddress).transfer(address(this),borrowingInfo.borrowingAmount);
        // 将抵押的奖励token，转移到个人账户
        ierc20B2.transfer(msg.sender,borrowingInfo.collateralReward);
        pool.borrowingRewardAmount -= borrowingInfo.collateralReward;

        borrowingInfo.borrowingAmount = 0;
        borrowingInfo.borrowLastTime = block.timestamp;
        borrowingInfo.collateralReward = 0;

        emit Redeem(_pid,borrowAmt,collateralReward,accumulateInterest,msg.sender);

    }

    /**
     * 结算，用于将用户借出去的token,还给用户,并同时计算利息以及
     * 奖励的token数据
     */
    function settle(uint256 _pid) external nonReentrant {
        require(block.timestamp > lockPeriod, "the time is locked");
        Pool storage pool = pools[_pid];
        LandingInfo storage landingInfo = landingValues[pool.stTokenAddress][msg.sender];
        // 先进行利息计算
        uint256 timePeriod = block.timestamp - landingInfo.landingLastTime;
        landingInfo.accumulateInterest += landingInfo.landingAmount * timePeriod * lendingInterestRate * 1e36/(365 * 24 * 3600);
        landingInfo.accumulateRewardInterest += landingInfo.landingRewardAmount * timePeriod * lendingRewardInterestRate * 1e36/(365 * 24 * 3600);

        pool.lendingAmount -=landingInfo.landingAmount;
        pool.lendingRewardAmount -=landingInfo.landingRewardAmount;

        uint256 landingAmount = landingInfo.landingAmount;
        uint256 landingRewardAmount = landingInfo.landingRewardAmount;

        landingInfo.landingAmount = 0;
        landingInfo.landingRewardAmount = 0;
        landingInfo.landingLastTime = block.timestamp;

        // 先将token 池子中的token返回给客户
        if(landingAmount > 0){
            IERC20(pool.stTokenAddress).transfer(msg.sender,landingAmount);
        }
        // 再将借出去的奖励token 返回给客户
        if(landingRewardAmount > 0){
            ierc20B2.transfer(msg.sender,landingRewardAmount);
        }
        // 最后将利息给到客户
        uint256 totalInterest = landingInfo.accumulateInterest + landingInfo.accumulateRewardInterest;
        if(totalInterest>0){
            interestToken.transfer(msg.sender,totalInterest);
        }

        emit Settle(_pid,landingAmount,landingRewardAmount,totalInterest,msg.sender);

    }


}