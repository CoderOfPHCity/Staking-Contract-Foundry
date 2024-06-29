// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

interface IDAGToken {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function safeTransferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IDAGOracle {
    function getLatestPrice() external view returns (int256);
    function decimals() external view returns (uint8);
}

contract Rstaking is ReentrancyGuard, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    IDAGToken public immutable stakingToken;
    IDAGOracle public immutable priceFeed;
    uint256 public constant MIN_DOLLAR_VALUE = 100; // $0.01 (adjust decimals as necessary)
    uint8 public constant MAX_APY = 100; // Example max APY, adjust as necessary

    address public daoWallet;
    address public penaltyWallet;
    uint8 public daoSplit = 80; // 80% to DAO

    struct StakeInfo {
        uint256 amount;
        uint256 startTime;
        uint256 lockupPeriod;
        uint256 apy;
        uint256 endTime;
    }

    struct StakingOption {
        uint256 apy;
        uint256 lockupPeriod;
        uint256 penalty;
    }

    mapping(address => StakeInfo[]) public stakes;
    mapping(address => uint256) public rewards;
    EnumerableSet.AddressSet private users;

    StakingOption[] public stakingOptions;
    address[] public topStakers;

    event Withdraw(address indexed user, uint256 amount);
    event Stake(address indexed user, uint256 amount, uint256 lockupPeriod, uint256 apy);
    event PenaltyPaid(address indexed user, uint256 penaltyAmount, address penaltyWallet);
    event DaoWalletUpdated(address indexed oldDaoWallet, address indexed newDaoWallet);
    event PenaltyWalletUpdated(address indexed oldPenaltyWallet, address indexed newPenaltyWallet);
    event DaoSplitUpdated(uint8 oldDaoSplit, uint8 newDaoSplit);
    event StakingOptionAdded(uint256 apy, uint256 lockupPeriod, uint256 penalty);
    event StakingOptionUpdated(uint256 index, uint256 apy, uint256 lockupPeriod, uint256 penalty);

    constructor(
        address initialOwner,
        address _stakingToken,
        address _priceFeed,
        address _daoWallet,
        address _penaltyWallet
    ) Ownable(initialOwner) {
        stakingToken = IDAGToken(_stakingToken);
        priceFeed = IDAGOracle(_priceFeed);
        daoWallet = _daoWallet;
        penaltyWallet = _penaltyWallet;

        // Initialize staking options based on the provided table
        stakingOptions.push(StakingOption(10, 5 days, 1));
        stakingOptions.push(StakingOption(20, 10 days, 2));
        stakingOptions.push(StakingOption(30, 20 days, 3));
        stakingOptions.push(StakingOption(50, 30 days, 5));
    }

    function getLatestPrice() public view returns (int256) {
        int256 price = priceFeed.getLatestPrice();
        require(price > 0, "Invalid price feed data");
        return price;
    }

    function withdraw(uint256 stakeIndex, uint256 amount) public nonReentrant {
        require(stakeIndex > 0 && stakeIndex <= stakes[msg.sender].length, "Invalid stake index");
        StakeInfo storage stakeInfo = stakes[msg.sender][stakeIndex - 1];

        uint256 userBalance = stakeInfo.amount;
        require(userBalance >= amount, "Insufficient balance");

        uint256 remainingBalance = userBalance - amount;

        int256 price = getLatestPrice();
        uint256 valueInDollars = (remainingBalance * uint256(price)) / (10 ** priceFeed.decimals());

        if (valueInDollars < MIN_DOLLAR_VALUE && block.timestamp < stakeInfo.endTime) {
            require(remainingBalance == 0, "Cannot withdraw below minimum dollar value during lockup period");
            amount = userBalance; // Withdraw the entire balance
        }

        uint256 penaltyAmount = 0;
        if (block.timestamp < stakeInfo.endTime) {
            penaltyAmount = (amount * getPenaltyRate(stakeInfo.lockupPeriod)) / 100;
            uint256 daoAmount = (penaltyAmount * daoSplit) / 100;
            uint256 penaltyWalletAmount = penaltyAmount - daoAmount;
            stakingToken.transfer(daoWallet, daoAmount);
            stakingToken.transfer(penaltyWallet, penaltyWalletAmount);
            emit PenaltyPaid(msg.sender, penaltyAmount, penaltyWallet);
        }

        stakeInfo.amount -= amount;
        stakingToken.transfer(msg.sender, amount - penaltyAmount);

        emit Withdraw(msg.sender, amount - penaltyAmount);
    }

    function stake(uint256 amount, uint256 stakingOptionIndex) public nonReentrant {
        require(amount > 0, "Cannot stake 0");
        require(stakingOptionIndex < stakingOptions.length, "Invalid staking option");

        StakingOption memory option = stakingOptions[stakingOptionIndex];
        uint256 lockupPeriod = option.lockupPeriod;
        uint256 apy = option.apy;

        uint256 userBalance = getTotalStakedAmount(msg.sender);
        uint256 newBalance = userBalance + amount;

        int256 price = getLatestPrice();
        uint256 valueInDollars = (newBalance * uint256(price)) / (10 ** priceFeed.decimals());

        require(valueInDollars >= MIN_DOLLAR_VALUE, "New balance is below the minimum threshold");
        require(stakingToken.allowance(msg.sender, address(this)) >= amount, "Allowance not enough");
        stakingToken.transferFrom(msg.sender, address(this), amount);
        stakes[msg.sender].push(
            StakeInfo({
                amount: newBalance,
                startTime: block.timestamp,
                lockupPeriod: lockupPeriod,
                endTime: block.timestamp + lockupPeriod,
                apy: apy
            })
        );

        emit Stake(msg.sender, amount, lockupPeriod, apy);
    }

    function getTotalStakedAmount(address user) public view returns (uint256) {
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < stakes[user].length; i++) {
            totalAmount += stakes[user][i].amount;
        }
        return totalAmount;
    }

    function getPenaltyRate(uint256 lockupPeriod) internal view returns (uint256) {
        for (uint256 i = 0; i < stakingOptions.length; i++) {
            if (stakingOptions[i].lockupPeriod == lockupPeriod) {
                return stakingOptions[i].penalty;
            }
        }
        return 1; // Default penalty for unspecified lockup period
    }

    function addStakingOption(uint256 apy, uint256 lockupPeriod, uint256 penalty) external onlyOwner {
        require(apy > 0 && apy <= MAX_APY, "Invalid APY");
        require(penalty <= 100, "Invalid penalty");
        stakingOptions.push(StakingOption(apy, lockupPeriod, penalty));
        emit StakingOptionAdded(apy, lockupPeriod, penalty);
    }

    function updateStakingOption(uint256 index, uint256 apy, uint256 lockupPeriod, uint256 penalty)
        external
        onlyOwner
    {
        require(index < stakingOptions.length, "Invalid index");
        require(apy > 0 && apy <= MAX_APY, "Invalid APY");
        require(penalty <= 100, "Invalid penalty");
        stakingOptions[index] = StakingOption(apy, lockupPeriod, penalty);
        emit StakingOptionUpdated(index, apy, lockupPeriod, penalty);
    }

    function setDaoWallet(address _daoWallet) external onlyOwner {
        emit DaoWalletUpdated(daoWallet, _daoWallet);
        daoWallet = _daoWallet;
    }

    function setPenaltyWallet(address _penaltyWallet) external onlyOwner {
        emit PenaltyWalletUpdated(penaltyWallet, _penaltyWallet);
        penaltyWallet = _penaltyWallet;
    }

    function setDaoSplit(uint8 _daoSplit) external onlyOwner {
        require(_daoSplit <= 100, "Invalid DAO split");
        emit DaoSplitUpdated(daoSplit, _daoSplit);
        daoSplit = _daoSplit;
    }

    function getStakingDetails(address user)
        external
        view
        returns (
            uint256[] memory amounts,
            uint256[] memory startTimes,
            uint256[] memory endTimes,
            uint256[] memory apys
        )
    {
        uint256 stakesCount = stakes[user].length;
        amounts = new uint256[](stakesCount);
        startTimes = new uint256[](stakesCount);
        endTimes = new uint256[](stakesCount);
        apys = new uint256[](stakesCount);

        for (uint256 i = 0; i < stakesCount; i++) {
            StakeInfo storage stakeInfo = stakes[user][i];
            amounts[i] = stakeInfo.amount;
            startTimes[i] = stakeInfo.startTime;
            endTimes[i] = stakeInfo.endTime;
            apys[i] = stakeInfo.apy;
        }
    }
}
