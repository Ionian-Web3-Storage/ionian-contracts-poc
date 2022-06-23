// SPDX-License-Identifier: Unlicense
pragma solidity =0.8.15;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

interface AccessControl {
    // do not use `view` so that we allow some bookkeeping
    function canAppend(address) external returns (bool);
}

interface IonianStructs {
    // TODO: optimize this with tight variable packing
    struct LogEntry {
        uint256[] streamIds;
        bytes data;
        bytes32 dataRoot;
        uint256 numChunks;
    }

    struct Stream {
        AccessControl ac;
    }
}

interface IonianEvents {
    event NewStream(uint256 id);
}

contract IonianLog is IonianStructs, IonianEvents {
    // ------------------ constants ------------------

    uint256 public constant MAX_STREAMS_PER_LOG = 10;

    // ------------------ state variables ------------------

    LogEntry[] public log;
    Stream[] public streams;

    // ------------------ initialization ------------------

    constructor() {
        // reserve stream #0
        streams.push(Stream(AccessControl(address(0))));
    }

    // ------------------ log management ------------------

    function appendLog(
        bytes calldata data,
        bytes32 dataRoot,
        uint256 numChunks
    ) external {
        require(
            data.length == 0 || dataRoot == bytes32(0),
            "Must specify one of data and dataRoot"
        );

        LogEntry memory entry;
        entry.data = data;
        entry.dataRoot = dataRoot;
        entry.numChunks = numChunks;

        log.push(entry);
    }

    function appendLog(
        uint256[] calldata streamIds,
        bytes calldata data,
        bytes32 dataRoot,
        uint256 numChunks
    ) external {
        require(
            data.length == 0 || dataRoot == bytes32(0),
            "Must specify one of data and dataRoot"
        );

        log.push(LogEntry(streamIds, data, dataRoot, numChunks));

        require(streamIds.length <= MAX_STREAMS_PER_LOG, "Error");

        for (uint256 ii = 0; ii < streamIds.length; ii++) {
            uint256 streamId = streamIds[ii];
            Stream memory stream = streams[streamId];

            if (stream.ac != AccessControl(address(0))) {
                require(stream.ac.canAppend(msg.sender), "Unauthorized");
            }
        }
    }

    // ------------------ stream management ------------------

    function createStream(AccessControl ac) external {
        uint256 id = streams.length;
        streams.push(Stream(ac));
        emit NewStream(id);
    }

    // ------------------ query interface ------------------

    function numLogs() external view returns (uint256) {
        return log.length;
    }

    function numStreams() external view returns (uint256) {
        return streams.length;
    }

    function getLogs(uint256 offset, uint256 limit)
        external
        view
        returns (LogEntry[] memory entries)
    {
        if (offset >= log.length) {
            return new LogEntry[](0);
        }

        uint256 endExclusive = Math.min(log.length, offset + limit);
        entries = new LogEntry[](endExclusive - offset);

        for (uint256 ii = offset; ii < endExclusive; ++ii) {
            entries[ii - offset] = log[ii];
        }
    }
}
