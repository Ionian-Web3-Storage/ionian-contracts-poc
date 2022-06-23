// SPDX-License-Identifier: Unlicense
pragma solidity =0.8.15;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface AccessControl {
    // do not use `view` so that we allow some bookkeeping
    function canAppend(address) external returns (bool);
}

interface IonianStructs {
    struct LogEntry {
        uint256[] streamIds;
        string data;
        bytes32 dataRoot;
    }

    struct Stream {
        uint256 id;
        AccessControl ac;
        uint256[] indices;
    }
}

interface IonianEvents {
    event NewStream(uint256 id);
}

contract IonianLog is IonianStructs, IonianEvents, ReentrancyGuard {
    // ------------------ constants ------------------

    uint256 public constant DEFAULT_STREAM = 0;
    uint256 public constant MAX_STREAMS_PER_LOG = 10;
    uint256 public constant UINT_MAX = 2**256 - 1;
    uint256 public constant MAX_DATA_LENGTH = 200;

    // ------------------ state variables ------------------

    LogEntry[] public log;
    uint256 public nextStreamId = 1;
    mapping(uint256 => Stream) public streams;

    // ------------------ log management ------------------

    function appendLog(string calldata data, bytes32 dataRoot)
        external
        nonReentrant
    {
        require(bytes(data).length <= MAX_DATA_LENGTH, "Error");

        uint256[] memory streamIds = new uint256[](1);
        streamIds[0] = DEFAULT_STREAM;
        log.push(LogEntry(streamIds, data, dataRoot));
    }

    function appendLog(
        uint256[] calldata streamIds,
        string calldata data,
        bytes32 dataRoot
    ) external nonReentrant {
        require(streamIds.length <= MAX_STREAMS_PER_LOG, "Error");
        require(bytes(data).length <= MAX_DATA_LENGTH, "Error");

        uint256 logId = log.length;
        log.push(LogEntry(streamIds, data, dataRoot));

        for (uint256 ii = 0; ii < streamIds.length; ii++) {
            uint256 streamId = streamIds[ii];
            Stream storage stream = streams[streamId];

            if (stream.ac != AccessControl(address(0))) {
                require(stream.ac.canAppend(msg.sender), "Unauthorized");
            }

            stream.indices.push(logId);
        }
    }

    // ------------------ stream management ------------------

    function createStream(AccessControl ac) external {
        uint256 id = nextStreamId++;

        streams[id].id = id;
        streams[id].ac = ac;

        emit NewStream(id);
    }

    // ------------------ query interface ------------------

    function belongsTo(uint256 logId, uint256[] memory streamIds)
        public
        view
        returns (bool)
    {
        for (uint256 ii = 0; ii < streamIds.length; ++ii) {
            for (uint256 jj = 0; jj < log[logId].streamIds.length; ++jj) {
                if (streamIds[ii] == log[logId].streamIds[jj]) {
                    return true;
                }
            }
        }

        return false;
    }

    function iterateStreams(
        uint256[] calldata streamIds,
        uint256 fromLogId,
        uint256 maxToReturn
    )
        external
        view
        returns (
            LogEntry[] memory result,
            uint256 num,
            uint256 next
        )
    {
        require(streamIds.length <= MAX_STREAMS_PER_LOG, "Error");

        result = new LogEntry[](maxToReturn);
        next = fromLogId;

        while (next < log.length && num < maxToReturn) {
            uint256 logId = next++;

            if (belongsTo(logId, streamIds)) {
                result[num++] = log[logId];
            }
        }
    }

    function iterateStreams2(
        uint256[] calldata streamIds,
        uint256[] calldata from,
        uint256 maxToReturn
    )
        external
        view
        returns (
            LogEntry[] memory result,
            uint256 num,
            uint256[] memory next
        )
    {
        require(streamIds.length <= MAX_STREAMS_PER_LOG, "Error");
        require(streamIds.length == from.length, "Error");

        result = new LogEntry[](maxToReturn);
        next = from;

        while (num < maxToReturn) {
            uint256 minLogId = UINT_MAX;

            // check next log id for streams, select the smallest
            for (uint256 ii = 0; ii < streamIds.length; ++ii) {
                uint256 streamId = streamIds[ii];
                uint256 nextId = next[ii];

                if (nextId >= streams[streamId].indices.length) {
                    continue;
                }

                uint256 logId = streams[streamId].indices[nextId];

                if (logId < minLogId) {
                    minLogId = logId;
                }
            }

            // all streams are exhausted
            if (minLogId == UINT_MAX) {
                return (result, num, next);
            }

            // collect result
            result[num++] = log[minLogId];

            // update next ids
            for (uint256 ii = 0; ii < streamIds.length; ++ii) {
                uint256 streamId = streamIds[ii];
                uint256 nextId = next[ii];

                if (nextId >= streams[streamId].indices.length) {
                    continue;
                }

                uint256 logId = streams[streamId].indices[nextId];

                if (logId == minLogId) {
                    next[ii] += 1;
                }
            }
        }
    }
}
