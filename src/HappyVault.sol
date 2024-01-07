// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract HappyVault is ReentrancyGuard, Ownable(msg.sender) {
    uint256 immutable SCALE = 1e18;
    struct Offering {
        address token;
        address payment_token;
        uint256 duration;
        uint256 amount;
        uint256 price;
        uint256 staking_start;
        uint256 staking_finish;
        uint256 vesting_start;
        uint256 rate;
        uint256 last_update;
        uint256 ticket_per_token_stored;
        uint256 total_paid;
        mapping(address => uint256) user_ticket_per_token;
        mapping(address => uint256) tickets;
        mapping(address => uint256) paid;
    }
    mapping(uint256 => Offering) public offerings;
    mapping(address => uint256) public balances;
    mapping(address => bool) public whitelist;
    uint256 public total_supply;
    uint256 public total_offerings;
    address public happy_token;

    constructor(address _happy_token) {
        happy_token = _happy_token;
    }

    error ZeroAmount();
    error ZeroAddress();
    error StakingNotFinished(uint256 _index);
    error NotWhitelisted(address _address);
    error RewardTooHigh(uint256 _index, uint256 _amount);
    error InsufficientDeserved(
        uint256 _index,
        uint256 _amount,
        uint256 _deserved
    );

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event OfferingCreated(uint256 indexed index);
    event Payment(address indexed user, uint256 indexed index, uint256 amount);

    function payLimited(uint256 _index, uint256 _amount) external {
        if (offerings[_index].staking_finish < block.timestamp)
            revert StakingNotFinished(_index);
        if (_amount > deserved(_index, msg.sender))
            revert InsufficientDeserved(
                _index,
                _amount,
                deserved(_index, msg.sender)
            );
        offerings[_index].tickets[msg.sender] -= _amount;
        offerings[_index].paid[msg.sender] += _amount;
        offerings[_index].total_paid += _amount;
        emit Payment(msg.sender, _index, _amount);
    }

    function payLimitless(uint256 _index, uint256 _amount) external {
        if (offerings[_index].staking_finish < block.timestamp)
            revert StakingNotFinished(_index);
        if (_amount + offerings[_index].total_paid > offerings[_index].amount)
            _amount = offerings[_index].amount - offerings[_index].total_paid;
        offerings[_index].tickets[msg.sender] -= _amount;
        offerings[_index].paid[msg.sender] += _amount;
        offerings[_index].total_paid += _amount;
        emit Payment(msg.sender, _index, _amount);
    }

    function addToWhitelist(address[] calldata addresses) external onlyOwner {
        for (uint256 i = 0; i < addresses.length; i++) {
            whitelist[addresses[i]] = true;
        }
    }

    function lastTimeRewardApplicable(uint256 _index)
        public
        view
        returns (uint256)
    {
        return
            block.timestamp < offerings[_index].staking_finish
                ? block.timestamp
                : offerings[_index].staking_finish;
    }

    function rewardPerToken(uint256 _index) public view returns (uint256) {
        if (total_supply == 0) {
            return offerings[_index].ticket_per_token_stored;
        }
        return
            offerings[_index].ticket_per_token_stored +
            ((lastTimeRewardApplicable(_index) -
                offerings[_index].last_update) *
                offerings[_index].rate *
                SCALE) /
            total_supply;
    }

    function deserved(uint256 _index, address _account)
        public
        view
        returns (uint256)
    {
        return
            ((balances[_account] *
                (rewardPerToken(_index) -
                    offerings[_index].user_ticket_per_token[_account])) /
                SCALE) + offerings[_index].tickets[_account];
    }

    function getRewardForDuration(uint256 _index)
        external
        view
        returns (uint256)
    {
        return offerings[_index].rate * offerings[_index].duration;
    }

    function stake(uint256 _amount)
        external
        nonReentrant
        updateTickets(msg.sender)
    {
        if (_amount == 0) revert ZeroAmount();
        if (!whitelist[msg.sender]) revert NotWhitelisted(msg.sender);
        total_supply += _amount;
        balances[msg.sender] += _amount;
        IERC20(happy_token).transferFrom(msg.sender, address(this), _amount);
        emit Staked(msg.sender, _amount);
    }

    function withdraw(uint256 _amount)
        public
        nonReentrant
        updateTickets(msg.sender)
    {
        if (_amount == 0) revert ZeroAmount();
        total_supply -= _amount;
        balances[msg.sender] -= _amount;
        IERC20(happy_token).transfer(msg.sender, _amount);
        emit Withdrawn(msg.sender, _amount);
    }

    function createOffering(
        address _token,
        address _payment_token,
        uint256 _duration, // TODO: maybe get tge date instead of duration
        uint256 _amount,
        uint256 _price
    ) public onlyOwner updateTicket(total_offerings, address(0)) {
        if (_token == address(0)) revert ZeroAddress();
        if (_payment_token == address(0)) revert ZeroAddress();
        if (_duration == 0) revert ZeroAmount();
        if (_amount == 0) revert ZeroAmount();
        if (_price == 0) revert ZeroAmount();
        offerings[total_offerings].token = _token;
        offerings[total_offerings].payment_token = _payment_token;
        offerings[total_offerings].duration = _duration;
        offerings[total_offerings].amount = _amount;
        offerings[total_offerings].price = _price;
        offerings[total_offerings].staking_start = block.timestamp;
        offerings[total_offerings].staking_finish = block.timestamp + _duration;
        offerings[total_offerings].last_update = block.timestamp;
        offerings[total_offerings].rate = _amount / _duration;
        total_offerings++;
        emit OfferingCreated(total_offerings);
    }

    modifier updateTicket(uint256 _index, address _account) {
        offerings[_index].ticket_per_token_stored = rewardPerToken(_index);
        offerings[_index].last_update = lastTimeRewardApplicable(_index);
        if (_account != address(0)) {
            offerings[_index].tickets[_account] = deserved(_index, _account);
            offerings[_index].user_ticket_per_token[_account] = offerings[
                _index
            ].ticket_per_token_stored;
        }
        _;
    }

    modifier updateTickets(address _account) {
        for (uint256 i = 0; i < total_offerings; i++) {
            if (offerings[i].staking_finish > block.timestamp) {
                offerings[i].ticket_per_token_stored = rewardPerToken(i);
                offerings[i].last_update = lastTimeRewardApplicable(i);
                if (_account != address(0)) {
                    offerings[i].tickets[_account] = deserved(i, _account);
                    offerings[i].user_ticket_per_token[_account] = offerings[i]
                        .ticket_per_token_stored;
                }
            }
        }
        _;
    }
}
