// 0.5.1-c8a2
// Enable optimization
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.6;

import "./MineIERC20.sol";
import "./MineSafeMath.sol";

/**
 * @title SimpleToken
 * @dev Very simple ERC20 Token example, where all tokens are pre-assigned to the creator.
 * Note they can later distribute these tokens as they wish using `transfer` and other
 * `ERC20` functions.
 */
contract MineOne {

    using MineSafeMath for uint256;

    // 首页基础数据
    struct BaseData {
        uint8 stage; // 当前期数（取值为：1,2,3,4）
        uint256 pledgeAmount; // 质押总量
        uint256 nextMineAmount; // 下次挖矿总量
        uint256 ownerPledgeAmount; // 我的质押
        uint256 ownerNextReward; // 我的下次挖到收益
        uint256 ownerMineReward; // 挖矿未领取奖励
        uint256 ownerMineDrawAmount; // 挖矿已领取奖励
        address ownerSuperior; // 用户的上级
        uint256 ownerInviteReward; // 邀请未领取奖励
        uint256 ownerInviteDrawAmount; // 邀请已领取奖励
        string dBossSymbol; // DBOSS符号
        uint256 dBossDecimals; // DBOSS精度
        string debSymbol; // DEB符号
        uint256 debDecimals; // DEB精度
    }

    // 挖矿数据
    struct MineData {
        address owner; // 挖矿者
        uint256 lastMineTime; // 最后一次挖矿时间
    }


    // 地址挖矿未领取收益
    mapping(address => uint256) private _addressMineRewards;

    // 地址挖矿已领取收益
    mapping(address => uint256) private _addressMineDrawAmounts;

    // 注册列表,存放上级地址
    mapping(address => address) private _registers;

    // 根用户
    address public root;

    // 地址邀请未领取收益
    mapping(address => uint256) private _addressInviteRewards;

    // 地址邀请已领取收益
    mapping(address => uint256) private _addressInviteDrawAmounts;

    // 最后一次挖矿的时间
    MineData[] public _mines;

    // 赎回天数
    uint256 _redeemDay = 90;

    // 当前阶段
    uint8 _stage = 1;

    // 最大阶段
    uint8 _maxStage = 4;

    // 阶段1挖矿占比
    uint8 _stage1 = 30;

    // 阶段2挖矿占比
    uint8 _stage2 = 25;

    // 阶段3挖矿占比
    uint8 _stage3 = 20;

    // 阶段4挖矿占比
    uint8 _stage4 = 25;

    // 邀请奖励的比例
    uint8 _inviteRewardRate = 15;

    // 挖矿总量
    uint256 public mineAmount;

    // 挖矿状态
    bool _mineStatus;

    // 邀请奖励总量
    uint256 public inviteAmount;

    address private _debToken;

    address private _dBossToken;

    address private _exchangeToken;

    address public _owner;

    //  是否初始化
    bool isInit = false;

    // 初始化时间，当天的零点
    uint256 public initTime;

    // 挖矿奖励事件（owner：当前用户，cate：分类（0：产矿，1：提取），amount：数量）
    event MineRewardLog(address owner, uint8 cate, uint256 amount);

    // 邀请奖励事件（owner：当前用户，from：来自哪个用户，为空表示提取，amount：数量）
    event InviteRewardLog(address owner, address from, uint256 amount);

    // 绑定上级事件（owner：当前用户，superior：上级地址）
    event BindSuperior(address owner, address superior);

    modifier onlyOwner{
        require(msg.sender == _owner);
        _;
    }

    /**
     * @dev Constructor that gives msg.sender all of existing tokens.
     */
    constructor (address debAddress, address dDossAddress, address exchangeAddress){
        _debToken = debAddress;
        _dBossToken = dDossAddress;
        _exchangeToken = exchangeAddress;
        _owner = msg.sender;
        mineAmount = 14700 * (10 ** MineIERC20(_dBossToken).decimals());
        inviteAmount = 1470 * (10 ** MineIERC20(_dBossToken).decimals());
    }

    /**
     * @dev 初始化
     */
    function init(address rootAddress) external {
        require(!isInit, "Cannot be re-initialized");

        uint256 amount = mineAmount.add(inviteAmount).mul(100).div(98);
        // 转入挖矿和邀请奖励的数量
        MineIERC20(_dBossToken).transferFrom(msg.sender, address(this), amount);
        isInit = true;
        root = rootAddress;
        // 设置根用户
        // 当前时间的零点 = 当前时间减去对 86400 取模，再减去一个 8小时（28800）
        initTime = block.timestamp.sub(block.timestamp.mod(86400)).sub(28800);
    }

    /**
    *  @dev 计算收益
    */
    function _calculateReward(uint256 amount, uint256 sumAmount) internal view returns  (uint256) {

        if (sumAmount == 0) {
            return 0;
        }

        // 把数量变大，来判断占比是否大于 0.000001%
        uint256 amountRate = amount * (10 ** 18) / sumAmount / (10 ** 8);

        if (amountRate < 1000) {
            // 占比小于 0.000001%
            return 0;
        }


        uint256 sum = _mineSumAmount();

        return sum.div(_redeemDay).mul(amount).div(sumAmount);

    }

    /**
    *  @dev 获取当前期的挖矿总量
    */
    function _mineSumAmount() internal view returns (uint256) {

        uint256 rewardRate;
        if (_stage == 1) {
            // 阶段1
            rewardRate = _stage1;
        } else if (_stage == 2) {
            // 阶段2
            rewardRate = _stage2;
        } else if (_stage == 3) {
            // 阶段3
            rewardRate = _stage3;
        } else if (_stage == 4) {
            // 阶段4
            rewardRate = _stage4;
        } else {
            return 0;
        }

        return mineAmount.mul(rewardRate).div(100);

    }

    /**
    *  @dev 领取挖矿收益
    */
    function addressMineDraw() external returns (bool) {

        uint256 reward = _addressMineRewards[msg.sender];

        require(reward > 0, "There are currently no available");

        // 清空未领取数量
        _addressMineRewards[msg.sender] = 0;

        // 增加已领取数量
        _addressMineDrawAmounts[msg.sender] = _addressMineDrawAmounts[msg.sender].add(reward);

        MineIERC20(_dBossToken).transfer(msg.sender, reward);

        emit MineRewardLog(msg.sender, 1, reward);
        return true;
    }

    /**
    *  @dev 领取邀请收益
    */
    function addressInviteDraw() external returns (bool) {

        uint256 reward = _addressInviteRewards[msg.sender];

        require(reward > 0, "There are currently no available");

        // 清空未领数量
        _addressInviteRewards[msg.sender] = 0;

        // 增加已领取数量
        _addressInviteDrawAmounts[msg.sender] = _addressInviteDrawAmounts[msg.sender].add(reward);

        MineIERC20(_dBossToken).transfer(msg.sender, reward);

        emit InviteRewardLog(msg.sender, address(0), reward);
        return true;
    }

    /**
    *  @dev 注册
    */
    function register(address superior) external returns (bool) {

        if (_registers[msg.sender] != address(0)) {
            return true;
        }
        // 上级不能是自己
        require(superior != msg.sender, "The superior cannot be himself ");

        _registers[msg.sender] = superior;

        MineData memory mineData;
        mineData.owner = msg.sender;
        mineData.lastMineTime = block.timestamp.sub(block.timestamp.mod(86400)).sub(28800);
        // 最后挖矿时间设置成昨天
        _mines.push(mineData);


        emit BindSuperior(msg.sender, superior);
        return true;
    }

    /**
    *  @dev 返回基础数据
    */
    function base() external view returns (BaseData memory) {

        uint256 uniAmount = MineIERC20(_exchangeToken).balanceOf(msg.sender);
        uint256 totalLiquidity =  MineIERC20(_exchangeToken).totalSupply();
        uint256 pledgeAmount = MineIERC20(_debToken).balanceOf(_exchangeToken);

        uint256 ownerPledgeAmount = uniAmount.mul(pledgeAmount) / totalLiquidity;
        BaseData memory baseData;
        baseData.stage = _stage;
        baseData.pledgeAmount = pledgeAmount;
        baseData.nextMineAmount = _mineSumAmount().div(_redeemDay);
        baseData.ownerPledgeAmount = ownerPledgeAmount;
        baseData.ownerNextReward = _calculateReward(ownerPledgeAmount, pledgeAmount);
        baseData.ownerMineReward = _addressMineRewards[msg.sender];
        baseData.ownerMineDrawAmount = _addressMineDrawAmounts[msg.sender];
        baseData.ownerSuperior = _registers[msg.sender];
        baseData.ownerInviteReward = _addressInviteRewards[msg.sender];
        baseData.ownerInviteDrawAmount = _addressInviteDrawAmounts[msg.sender];
        baseData.dBossSymbol = MineIERC20(_dBossToken).symbol();
        baseData.dBossDecimals = MineIERC20(_dBossToken).decimals();
        baseData.debSymbol = MineIERC20(_debToken).symbol();
        baseData.debDecimals = MineIERC20(_debToken).decimals();
        return baseData;
    }


    /**
    *  @dev 分页挖矿，返回挖矿数量，0表示没有可挖
    */
    function mine(uint256 page, uint256 pageSize) external onlyOwner returns (uint256) {

        pageSize = pageSize > 100 ? 100 : pageSize;

        uint256 start = (page - 1) * pageSize;
        uint256 end = (page) * pageSize;

        uint256 mineNum = 0;

        if (start >= _mines.length) {
            return mineNum;
        }
        if (end > _mines.length) {
            end = _mines.length;
        }

        // 当前时间的零点
        uint256 time0 = block.timestamp.sub(block.timestamp.mod(86400)).sub(28800);

        // 上次挖矿时间的零点
        uint256 lastTime = time0.sub(86400);

        uint256 tmpStage = time0.sub(initTime).div(86400);

        if (tmpStage <= _redeemDay) {
            _stage = 1;
        } else if (tmpStage <= _redeemDay.mul(2)) {
            _stage = 2;
        } else if (tmpStage <= _redeemDay.mul(3)) {
            _stage = 3;
        } else if (tmpStage <= _redeemDay.mul(4)) {
            _stage = 4;
        }

        require(_stage <= _maxStage, "The number of mining periods exceeds the maximum number of periods");

        if (!_mineStatus) {
            _mineStatus = true;
        }

        // 获取当前交易对的质押总量
        uint256 pledgeAmount = MineIERC20(_debToken).balanceOf(_exchangeToken);
        // 交易对总量
        uint256 totalLiquidity =  MineIERC20(_exchangeToken).totalSupply();

        // 没有总量
        if (totalLiquidity == 0) {
            return 0;
        }

        for (uint256 i = start; i < end; i++) {
            MineData memory mineData;
            mineData = _mines[i];
            // 上次挖矿时间不对
            if (mineData.lastMineTime != lastTime) {
                continue;
            }
            /* ########## 挖矿 ########### */

            // 获取当前挖矿者的质押总量
            uint256 uniAmount = MineIERC20(_exchangeToken).balanceOf(mineData.owner);
            uint256 ownerPledgeAmount = uniAmount.mul(pledgeAmount) / totalLiquidity;

            // 生成奖励
            uint256 reward = _calculateReward(ownerPledgeAmount, pledgeAmount);

            if (reward > 0) {
                _addressMineRewards[mineData.owner] = _addressMineRewards[mineData.owner].add(reward);

                // 如果有上级计算层级奖励
                address superior = _registers[mineData.owner];
                uint256 superiorReward = 0;
                if (superior != address(0)) {
                    superiorReward = reward.mul(_inviteRewardRate).div(100);
                    if (superiorReward > 0) {
                        _addressInviteRewards[superior] = _addressInviteRewards[superior].add(superiorReward);
                    }
                }

                emit MineRewardLog(mineData.owner, 0, reward);
                if (superiorReward > 0) {
                    emit InviteRewardLog(superior, mineData.owner, superiorReward);
                }
            }


            mineData.lastMineTime = mineData.lastMineTime.add(86400);
            _mines[i] = mineData;
            mineNum++;
        }

        if (mineNum == 0) {
            _mineStatus = false;
        }

        return mineNum;
    }

    /**
    *  @dev 更换管理员
    */
    function setOwner(address addr) external onlyOwner returns (bool) {
        _owner = addr;
        return true;
    }

}