// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Push baseline via dead-weight capital:
/// - payer must pre-deposit (lock) funds into this contract
/// - anyone can crank releases, but releases *locked* funds (not payer wallet liquidity)
contract PushLockbox {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;
    address public immutable payer;
    address public immutable receiver;

    uint64 public immutable start;
    uint64 public immutable end;
    uint256 public immutable total;

    uint256 public released;

    event Deposited(uint256 amount);
    event Cranked(uint256 amount, uint256 cumulative);

    constructor(address token_, address payer_, address receiver_, uint64 start_, uint64 end_, uint256 total_) {
        require(token_ != address(0) && payer_ != address(0) && receiver_ != address(0), "BAD_ADDR");
        require(end_ > start_, "BAD_WINDOW");
        require(total_ > 0, "BAD_TOTAL");
        token = IERC20(token_);
        payer = payer_;
        receiver = receiver_;
        start = start_;
        end = end_;
        total = total_;
    }

    function deposit() external {
        require(msg.sender == payer, "NOT_PAYER");
        token.safeTransferFrom(payer, address(this), total);
        emit Deposited(total);
    }

    function unlockedAt(uint64 t) public view returns (uint256) {
        if (t <= start) return 0;
        if (t >= end) return total;
        uint256 elapsed = uint256(t - start);
        uint256 dur = uint256(end - start);
        return (total * elapsed) / dur;
    }

    function owedNow() public view returns (uint256) {
        uint256 unlocked = unlockedAt(uint64(block.timestamp));
        if (unlocked <= released) return 0;
        return unlocked - released;
    }

    function crank() external returns (uint256 amt) {
        amt = owedNow();
        require(amt > 0, "NOTHING_OWED");
        released += amt;
        token.safeTransfer(receiver, amt);
        emit Cranked(amt, released);
    }
}
