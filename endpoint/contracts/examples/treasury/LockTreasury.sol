// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IEndpoint} from "../../interfaces/IEndpoint.sol";

contract LockTreasury {
    using SafeERC20 for IERC20Metadata;

    uint256 private _rid;

    address private _rua;

    address private _endpoint;

    modifier onlyEndpoint() {
        require(msg.sender == _endpoint, "only endpoint");
        _;
    }

    function init(uint256 rid, address rua, address endpoint) external {
        _rid = rid;
        _rua = rua;
        _endpoint = endpoint;
    }

    function lock(address token, uint256 amount) external {
        IERC20Metadata(token).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
        string memory name = IERC20Metadata(token).name();
        string memory symbol = IERC20Metadata(token).symbol();
        bytes memory data = abi.encodeWithSelector(
            bytes4(keccak256("mint(address,string,string,address,uint256)")),
            token,
            name,
            symbol,
            msg.sender,
            amount
        );
        IEndpoint(_endpoint).send(_rid, _rua, data);
    }

    function unlock(address token, uint256 amount) external onlyEndpoint {
        IERC20Metadata(token).safeTransfer(msg.sender, amount);
    }
}
