// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IFullCheckpoint} from "./interfaces/IFullCheckpoint.sol";
import {RLPEncode} from "./libraries/RLPEncode.sol";

contract Endpoint is Ownable {
    struct Config {
        IFullCheckpoint checkpoint;
    }

    struct Receipt {
        bytes postState;
        uint256 status;
        uint256 cumulativeGasUsed;
        bytes bloom;
        bytes[] logs;
        bytes txHash;
        address contractAddress;
        uint256 gasUsed;
    }

    Config private _config;

    // txHash => payload
    mapping(bytes => bytes) private _payloads;

    event Packet(bytes payload);

    event PacketReceived(bytes payload);

    function send(bytes calldata payload) external {
        emit Packet(payload);
    }

    function getPayload(
        bytes calldata txHash
    ) external view returns (bytes memory) {
        return _payloads[txHash];
    }

    function validateTransactionProof(
        bytes calldata leaf,
        bytes32[] calldata proof,
        bytes32 blockHash
    ) external {
        IFullCheckpoint checkpoint = getConfig().checkpoint;
        bytes32 receiptRoot = checkpoint.getReceiptHash(blockHash);
        require(MerkleProof.verify(proof, receiptRoot, leaf), "invalid proof");

        Receipt memory receipt = getReceipt(leaf);
        // TODO
        bytes memory payload = receipt.logs[0];
        _payloads[receipt.txHash] = payload;
        emit PacketReceived(payload);
    }

    function getConfig() public view returns (Config memory) {
        require(
            _config.checkpoint != IFullCheckpoint(address(0)),
            "no checkpoint"
        );
        return _config;
    }

    function setConfig(Config calldata config) external onlyOwner {
        require(
            config.checkpoint != IFullCheckpoint(address(0)),
            "invalid checkpoint"
        );
        _config = config;
    }

    function getReceipt(bytes leaf) public pure returns (Receipt memory) {
        return new Receipt();
    }
}
