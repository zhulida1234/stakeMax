// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./IERC20.sol";
import "./ERC20.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract MaxStake is Initializable,UUPSUpgradeable,AccessControlUpgradeable,PausableUpgradeable{

    //奖励代币
    IERC20 public ierc20B2;
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
    }

    Pool[] public pools;

    struct User {
        // 用户质押的代币数量
        uint256 stAmount;
        // 用户已经分配的奖励代币数量
        uint256 finishedB2;
        // 用户待分配的奖励代币数量
        uint256 pendingB2;
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
        pools.push(Pool({stTokenAddress:_tokenAddr,poolWeight:_poolWeight,lastRewardBlock:_lastRewardBlock,accB2PerST:0,stTokenAmount:0,minDepositAmount:_minDepositAmount,unstakeLockedBlocks:_unstakeLockedBlocks}));
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

}