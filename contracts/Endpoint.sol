// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MerklePatricia} from "@polytope-labs/solidity-merkle-trees/src/MerklePatricia.sol";
import {IFullCheckpoint} from "./interfaces/IFullCheckpoint.sol";
import {RLPReader} from "./libraries/RLPReader.sol";

/**
 * @title XDC Zero Endpoint
 * @author Galaxy
 * @notice Cross chain infra contract that receives packet and send packet to different chain
 */
contract Endpoint is Ownable {
    using RLPReader for bytes;
    using RLPReader for RLPReader.RLPItem;
    using MerklePatricia for bytes32;

    /**
     * @dev csc is the checkpoint contract of the receive chain
     * @dev endpoint is the address of the endpoint contract of the send chain
     */
    struct Chain {
        IFullCheckpoint csc;
        address endpoint;
    }

    /**
     * @dev log of the receipt
     */
    struct Log {
        address address_;
        bytes32[] topics;
        bytes data;
    }
    /**
     * @dev receipt of the transaction
     */
    struct Receipt {
        bytes postStateOrStatus;
        uint64 cumulativeGasUsed;
        bytes bloom;
        Log[] logs;
    }

    mapping(uint256 => Chain) private _chains;

    /**
     * @dev chainId of the current chain
     */
    uint256 private _chainId;

    /**
     * @dev payload of the transaction 
     */
    mapping(bytes => bytes) private _payloads;

    event Packet(bytes payload);

    event PacketReceived(uint256 chainId, address ua, bytes content);

    /**
     * @dev initialize the contract
     * @param chainId chainId of the current chain
     */
    function initialize(uint256 chainId) external {
        _chainId = chainId;
    }

    function packetHash() private pure returns (bytes32) {
        return keccak256("Packet(bytes)");
    }

    function send(bytes calldata content) external {
        require(_chainId != 0, "chainId not set");
        address ua = msg.sender;
        bytes memory payload = abi.encode(_chainId, ua, content);
        emit Packet(payload);
    }

    function getPayload(
        bytes calldata txHash
    ) external view returns (bytes memory) {
        return _payloads[txHash];
    }

    /**
     * @dev validate transaction proof and save payload
     * @param sChainId chainId of the send chain
     * @param key key of the receipt mekle tree
     * @param proof proof of the key of receipt mekle tree
     * @param blockHash blockHash of the receipt
     */
    function validateTransactionProof(
        uint256 sChainId,
        bytes memory key,
        bytes[] calldata proof,
        bytes32 blockHash
    ) external {
        Chain memory chain = _chains[sChainId];
        IFullCheckpoint csc = chain.csc;
        require(csc != IFullCheckpoint(address(0)), "chainId not registered");

        bytes32 receiptRoot = csc.getReceiptHash(blockHash);

        bytes[] memory keys = new bytes[](1);
        keys[0] = key;
        bytes memory receiptRlp = receiptRoot
        .VerifyEthereumProof(proof, keys)[0].value;

        require(receiptRlp.length > 0, "invalid proof");

        Receipt memory receipt = getReceipt(receiptRlp);

        for (uint256 i = 0; i < receipt.logs.length; i++) {
            if (
                receipt.logs[i].topics[0] == packetHash() &&
                receipt.logs[i].address_ == chain.endpoint
            ) {
                bytes memory payload = receipt.logs[i].data;
                (uint256 chainId, address ua, bytes memory content) = abi
                    .decode(payload, (uint256, address, bytes));

                emit PacketReceived(chainId, ua, content);
                break;
            }
        }
    }

    /**
     * @dev register a chain
     * @param chainId chainId of the send chain
     * @param csc checkpoint contract of the receive chain
     * @param endpoint endpoint contract of the send chain
     */
    function registerChain(
        uint256 chainId,
        IFullCheckpoint csc,
        address endpoint
    ) external onlyOwner {
        _chains[chainId] = Chain(csc, endpoint);
    }

    /**
     * @dev get receipt from rlp
     * @param receiptRlp receipt rlp
     */
    function getReceipt(
        bytes memory receiptRlp
    ) public pure returns (Receipt memory) {
        RLPReader.RLPItem[] memory items = receiptRlp.toRlpItem().toList();

        Receipt memory receipt;
        receipt.postStateOrStatus = items[0].toBytes();
        receipt.cumulativeGasUsed = uint64(items[1].toUint());
        receipt.bloom = items[2].toBytes();
        // Decode logs
        RLPReader.RLPItem[] memory rlpLogs = items[3].toList();
        Log[] memory logs = new Log[](rlpLogs.length);
        for (uint256 i = 0; i < rlpLogs.length; i++) {
            RLPReader.RLPItem[] memory logItems = rlpLogs[i].toList();
            logs[i].address_ = logItems[0].toAddress();
            RLPReader.RLPItem[] memory topicsItems = logItems[1].toList();
            bytes32[] memory topics = new bytes32[](topicsItems.length);
            for (uint256 j = 0; j < topicsItems.length; j++) {
                topics[j] = bytes32(topicsItems[j].toUint());
            }
            logs[i].topics = topics;
            logs[i].data = logItems[2].toBytes();
        }
        receipt.logs = logs;
        return receipt;
    }
}
