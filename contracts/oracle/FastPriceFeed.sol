// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./interfaces/IPriceFeed.sol";

contract FastPriceFeed is IPriceFeed {
    address public gov;
    address public override aggregator;
    uint256 public answer;
    string public override description = "FastPriceFeed";
    uint256 public decimals;
    uint80 public roundId;

    mapping(uint80 => uint256) public answers;
    mapping(uint80 => uint256) public latestAts;
    mapping(address => bool) public isAdmin;

    event SetAdmin(address indexed account, bool isAdmin);
    event SetDecription(string description);
    event SetLatestAnswer(uint256 answer);

    constructor() {
        gov = msg.sender;
        isAdmin[msg.sender] = true;
    }

    function setAdmin(address _account, bool _isAdmin) external {
        require(msg.sender == gov, "PriceFeed: forbidden");
        isAdmin[_account] = _isAdmin;
        emit SetAdmin(_account, _isAdmin);
    }

    function setDescription(string memory _description) external {
        require(isAdmin[msg.sender], "PriceFeed: forbidden");
        description = _description;
        emit SetDecription(_description);
    }

    function setLatestAnswer(uint256 _answer) external {
        require(isAdmin[msg.sender], "PriceFeed: forbidden");
        roundId = roundId + 1;
        answer = _answer;
        answers[roundId] = _answer;
        latestAts[roundId] = block.timestamp;
        emit SetLatestAnswer(_answer);
    }

    function latestAnswer() external view override returns (uint256) {
        return answer;
    }

    function latestRound() external view override returns (uint80) {
        return roundId;
    }

    // returns roundId, answer, startedAt, updatedAt, answeredInRound
    function getRoundData(uint80 _roundId) external view override returns (uint80, uint256, uint256, uint256, uint80) {
        return (_roundId, answers[_roundId], latestAts[roundId], 0, 0);
    }
}
