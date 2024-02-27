// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract TokenStaking is ReentrancyGuard {

    struct User {

        uint256 tokensStaked;
        uint256 totalRewards;

        uint256 lastStakeBlock;
        uint256 lastRewardCalculationBlock;

        uint256 rewardsClaimedSoFar;
        uint256 lastRewardClaimBlock;

    }

    mapping(address => User) private userDetails;

    address public owner;

    IERC20 public stakeToken;
    IERC20 public rewardToken;

    uint256 public stakingStartDate;
    uint256 public stakingEndDate;

    uint256 public minStakingAmount;
    uint256 public maxStakingAmount;

    uint256 public totalUsers;
    uint256 public totalStakedTokens;
    uint256 public apy; // reward rate
    uint256 public daysOfStaking;
    uint256 public earlyUnstakeFeePercentage;

    uint256 constant PERCENTAGE_DENOMINATOR = 1000;
    uint256 constant REWARD_PERCENTAGE_THRESHOLD = 10;

    bool public isStakingPaused;

    event Staked(address indexed user, uint256 indexed amount);
    event Unstaked(address indexed user, uint256 indexed amount);
    event RewardsClaimed(address indexed user, uint256 indexed amount);
    event EarlyUnstake(address indexed user, uint256 indexed amount);

    constructor(
        address _stakeToken,
        address _rewardToken,
        uint256 _stakingStartDate,
        uint256 _stakingEndDate,
        uint256 _apy,
        uint256 _daysOfStaking,
        uint256 _minStakingAmount,
        uint256 _maxStakingAmount,
        uint256 _earlyUnstakeFeePercentage
    ) {
        owner = msg.sender;
        stakeToken = IERC20(_stakeToken);
        rewardToken = IERC20(_rewardToken);
        stakingEndDate = _stakingEndDate;
        stakingStartDate = _stakingStartDate;
        minStakingAmount = _minStakingAmount;
        maxStakingAmount = _maxStakingAmount;
        earlyUnstakeFeePercentage = _earlyUnstakeFeePercentage;
        apy = _apy;
        daysOfStaking = _daysOfStaking;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can access this function");
        _;
    }

    modifier whenContractHasBalance(uint256 _amount) {
        require(
            stakeToken.balanceOf(address(this)) >= _amount,
            "Insufficient funds right now, please try later"
        );
        _;
    }

    // View Functions

    function getStakingStartDate() external view returns (uint256) {
        return stakingStartDate;
    }

    function getStakingEndDate() external view returns (uint256) {
        return stakingEndDate;
    }

    function getMinimumStakingAmount() external view returns (uint256) {
        return minStakingAmount;
    }

    function getMaximumStakingAmount() external view returns (uint256) {
        return maxStakingAmount;
    }

    function getRewardRate() external view returns (uint256) {
        return apy;
    }

    function getEarlyUnstakeFeePercentage() external view returns (uint256) {
        return earlyUnstakeFeePercentage;
    }

    function getDaysOfStaking() external view returns (uint256) {
        return daysOfStaking;
    }

    function checkStakingStatus() external view returns (bool) {
        return isStakingPaused;
    }

    function getUserEstimatedRewards() external view returns (uint256) {

        (uint256 amount, ) = _getUserEstimatedRewards(msg.sender);

        return userDetails[msg.sender].totalRewards + amount;

    }

    function getWithdrawbleAmount() external view returns (uint256) {
        return (stakeToken.balanceOf(address(this)) - totalStakedTokens);
    }

    function getUserDetails(address _userAddress)
        external
        view
        returns (User memory)
    {
        return userDetails[_userAddress];
    }

    function isUserStakeHolder(address _userAddress)
        external
        view
        returns (bool)
    {
        return userDetails[_userAddress].tokensStaked > 0;
    }

    // End Of View Methods

    // Owner Methods

    function updateMinimumStakingAmount(uint256 _updatedAmount)
        external
        onlyOwner
    {
        require(_updatedAmount > 0, "Updated Amount Cannot be 0");
        minStakingAmount = _updatedAmount;
    }

    function updateMaximumStakingAmount(uint256 _updatedAmount)
        external
        onlyOwner
    {
        require(_updatedAmount > 0, "Updated Amount cannot be 0");
        maxStakingAmount = _updatedAmount;
    }

    function updateStakingEndDate(uint256 _updatedDate) external onlyOwner {
        require(
            _updatedDate > block.timestamp,
            "You can set only future date there"
        );
        stakingEndDate = _updatedDate;
    }

    function updateEarlyUnstakeFee(uint256 _updatedFee) external onlyOwner {
        require(_updatedFee > 0, "Updated fee cannot be 0");
        earlyUnstakeFeePercentage = _updatedFee;
    }

    function stakeTokenForUser(address _userAddress, uint256 _amount)
        external
        onlyOwner
        nonReentrant
    {
        _stakeTokens(_userAddress, _amount);
    }

    function changeStakingStatus() external onlyOwner {
        isStakingPaused = !isStakingPaused;
    }

    function withdrawTokens(uint256 _amount)
        external
        nonReentrant
        onlyOwner
    {
        require(
            this.getWithdrawbleAmount() >= _amount,
            "Not Enough Balance In Contract"
        );
        stakeToken.transfer(msg.sender, _amount);
    }

    // End Of Owner Functions

    // User Methods

    function Stake(uint256 _amount) external nonReentrant {
        _stakeTokens(msg.sender, _amount);
    }

    function _stakeTokens(address _userAddress, uint256 _amount) internal {
        require(
            _userAddress != address(0),
            "Please Enter A Valid Address"
        );
        require(
            isStakingPaused == false,
            "staking has been stopped"
        );
        require(
            _amount >= minStakingAmount,
            "Amount must be greater than mininmum staking amount"
        );
        require(
            maxStakingAmount >= totalStakedTokens + _amount,
            "Maximum staking limit has been reached"
        );

        uint256 currentBlock = getCurrentBlock();

        uint256 currentTime = getCurrentTime();

        require(
            currentTime > stakingStartDate,
            "Staking has not started yet"
        );
        require(
            stakingEndDate > currentTime,
            "Staking has already ended"
        );

        if (userDetails[_userAddress].tokensStaked > 0) {

            _calculateRewards(_userAddress);

        } 
        else {

            userDetails[_userAddress].lastRewardCalculationBlock = currentBlock;

            totalUsers += 1;



        }

        userDetails[_userAddress].lastStakeBlock = currentBlock;
        userDetails[_userAddress].tokensStaked += _amount;
        totalStakedTokens += _amount;

        require(
            stakeToken.transferFrom(msg.sender, address(this), _amount),
            "stakeToken Staking Failed"
        );

        emit Staked(_userAddress, _amount);
    }

    function Unstake(uint256 _amount)
        external
        whenContractHasBalance(_amount)
        nonReentrant
    {
        address user = msg.sender;

        require(_amount > 0, "You cannot unstake 0 amount of stakeTokens");
        require(
            this.isUserStakeHolder(user),
            "You haven't staked anything"
        );
        require(
            userDetails[user].tokensStaked >= _amount,
            "You haven't staked this much amount of stakeTokens"
        );

        uint256 currentBlock = block.number;
        _calculateRewards(user);

        uint256 earlyUnstakeFee;
        if (
            userDetails[user].lastStakeBlock + daysOfStaking >= currentBlock
        ) {
            earlyUnstakeFee = ((_amount * earlyUnstakeFeePercentage) /
                PERCENTAGE_DENOMINATOR);
            emit EarlyUnstake(user, earlyUnstakeFee);
        }

        uint256 amountToTransfer = _amount - earlyUnstakeFee;

        userDetails[user].tokensStaked -= _amount;
        totalStakedTokens -= _amount;

        if (userDetails[user].tokensStaked == 0) {
            delete userDetails[user];
            totalUsers -= 1;
        }

        require(
            stakeToken.transfer(user, amountToTransfer),
            "stakeToken Unstaking Failed"
        );

        emit Unstaked(user, _amount);
    }

    function claimRewards() external nonReentrant whenContractHasBalance(userDetails[msg.sender].totalRewards) {
        // uint256 currentBlock = block.number;
        _calculateRewards(msg.sender);

        uint256 rewardAmount = userDetails[msg.sender].totalRewards;
        require(rewardAmount > 0, "You dont have any amount to claim");

        require(
            rewardToken.transfer(msg.sender, rewardAmount),
            "Rewards Claimed Failed"
        );

        userDetails[msg.sender].totalRewards = 0;
        userDetails[msg.sender].rewardsClaimedSoFar += rewardAmount;

        emit RewardsClaimed(msg.sender, rewardAmount);
    }

    // End Of User Methods

    // Helper Functions

    function _calculateRewards(address _user) internal {
        (uint256 userReward, uint256 currentBlock) = _getUserEstimatedRewards(_user);
        userDetails[_user].totalRewards += userReward;
        userDetails[_user].lastRewardCalculationBlock = currentBlock;
    }

    

    function _getUserEstimatedRewards(address _user) internal view returns (uint256, uint256) {

      uint256 userReward;

      uint256 userBlock = userDetails[_user].lastRewardCalculationBlock;

      uint256 currentBlock = getCurrentBlock();

     if (currentBlock > userDetails[_user].lastStakeBlock) {
        
        userReward = ((currentBlock - userBlock) * userDetails[_user].tokensStaked * apy) / PERCENTAGE_DENOMINATOR;
        
     }

      return (userReward, currentBlock);
 }

 function getCurrentTime() view internal returns(uint256){

    return block.timestamp;

 }

 function getCurrentBlock() view internal returns(uint256){

    return block.number;

 }
}