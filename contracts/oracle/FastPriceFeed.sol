// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./interfaces/IPriceFeed.sol";

contract FastPriceFeed is IPriceFeed {
    address public gov;
    mapping(address=>uint256) public ts;
    mapping(address=>uint256) public answer;
    string public override description = "FastPriceFeed";
    uint256 public decimals;
    mapping(address=>uint80) public roundId;

    mapping(address=>mapping(uint80 => uint256)) public answers;
    mapping(address=>mapping(uint80 => uint256)) public latestAts;
    mapping(address => bool) public isAdmin;

    event SetAdmin(address indexed account, bool isAdmin);
    event SetDecription(string description);
    event SetAnswer(address token, uint256 ts, uint256 answer);

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

    function setAnswer(address _token, uint256 _ts, uint256 _answer) public override {
        require(isAdmin[msg.sender], "PriceFeed: forbidden");
        if(_ts >= ts[_token]) {
            uint80 r = ++roundId[_token];
            answer[_token] = _answer;
            ts[_token] = _ts;
            answers[_token][r] = _answer;
            latestAts[_token][r] = _ts;
            emit SetAnswer(_token, _ts, _answer);
        }
    }

    function setLatestAnswer(address _token, uint256 _answer) external {
        setAnswer(_token, block.timestamp, _answer);
    }

    function latestAnswer(address _token) external view override returns (uint256) {
        return answer[_token];
    }

    function latestRound(address _token) external view override returns (uint80) {
        return roundId[_token];
    }

    // returns roundId, answer, startedAt, updatedAt, answeredInRound
    function getRoundData(address _token, uint80 _roundId) external view override returns (uint80, uint256, uint256, uint256, uint80) {
        return (_roundId, answers[_token][_roundId], latestAts[_token][_roundId], 0, 0);
    }
}
