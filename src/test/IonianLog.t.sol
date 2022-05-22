// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {DSTest} from "ds-test/test.sol";
import {Utilities} from "./utils/Utilities.sol";
import {console} from "./utils/Console.sol";
import {Vm} from "forge-std/Vm.sol";

import {IonianLog, AccessControl, IonianStructs, IonianEvents} from "../IonianLog.sol";

contract SimpleAccessControl is AccessControl {
    mapping(address => bool) public approved;

    constructor() {
        approved[msg.sender] = true;
    }

    function approve(address addr) external {
        approved[addr] = true;
    }

    function canAppend(address addr) external view returns (bool) {
        return approved[addr];
    }
}

contract BaseSetup is DSTest, IonianStructs, IonianEvents {
    Vm internal immutable vm = Vm(HEVM_ADDRESS);

    Utilities internal utils;
    address payable[] internal users;

    address internal alice;
    address internal bob;

    IonianLog internal ionian;

    uint256[] internal stream1only;
    uint256[] internal stream2only;
    uint256[] internal streams1and2;

    function setUp() public virtual {
        utils = new Utilities();
        users = utils.createUsers(5);

        alice = users[0];
        vm.label(alice, "Alice");

        bob = users[1];
        vm.label(bob, "Bob");

        ionian = new IonianLog();
        vm.label(address(ionian), "Ionian Log");

        stream1only = new uint256[](1);
        stream1only[0] = 1;

        stream2only = new uint256[](1);
        stream2only[0] = 2;

        streams1and2 = new uint256[](2);
        streams1and2[0] = 1;
        streams1and2[1] = 2;
    }
}

contract SimpleAppend is BaseSetup {
    function setUp() public virtual override {
        BaseSetup.setUp();
    }

    function testSimpleAppend() public {
        // new stream by Alice
        vm.startPrank(alice);

        vm.expectEmit(true, true, true, true, address(ionian));
        emit NewStream(1);

        ionian.createStream(AccessControl(address(0)));
        ionian.appendLog(stream1only, "data1", bytes32("root1"));

        vm.stopPrank();
    }
}

contract AppendWithAccessControl is BaseSetup {
    function setUp() public virtual override {
        BaseSetup.setUp();
    }

    function testAccessControl() public {
        // new stream by Alice
        vm.startPrank(alice);
        ionian.createStream(AccessControl(address(0)));
        ionian.appendLog(stream1only, "data1", bytes32("root1"));
        vm.stopPrank();

        // new stream by Bob
        vm.startPrank(bob);
        SimpleAccessControl ac = new SimpleAccessControl();
        ionian.createStream(ac);
        ionian.appendLog(stream2only, "data2", bytes32("root2"));
        vm.stopPrank();

        // access denied
        vm.startPrank(alice);
        vm.expectRevert("Unauthorized");
        ionian.appendLog(streams1and2, "data3", bytes32("root3"));
        vm.stopPrank();

        // grant access
        vm.prank(bob);
        ac.approve(alice);

        vm.prank(alice);
        ionian.appendLog(streams1and2, "data3", bytes32("root3"));
    }
}

contract ShortStreamQueries is BaseSetup {
    uint256 public constant MAX = 5;

    function setUp() public virtual override {
        BaseSetup.setUp();

        // create two streams
        vm.startPrank(alice);
        ionian.createStream(AccessControl(address(0)));
        ionian.createStream(AccessControl(address(0)));

        // create log
        ionian.appendLog(stream1only, "data1", bytes32("root1"));
        ionian.appendLog(stream2only, "data2", bytes32("root2"));
        ionian.appendLog(streams1and2, "data3", bytes32("root3"));
        vm.stopPrank();
    }

    function testFewLogs1() public {
        LogEntry[] memory entries;
        uint256 num;
        uint256 next;

        // stream #1
        (entries, num, next) = ionian.iterateStreams(stream1only, 0, MAX);

        assertEq(num, 2);
        assertEq(next, 3);
        assertEq(entries[0].dataRoot, bytes32("root1"));
        assertEq(entries[1].dataRoot, bytes32("root3"));

        // stream #2
        (entries, num, next) = ionian.iterateStreams(stream2only, 0, MAX);

        assertEq(num, 2);
        assertEq(next, 3);
        assertEq(entries[0].dataRoot, bytes32("root2"));
        assertEq(entries[1].dataRoot, bytes32("root3"));

        // streams #1 and #2
        (entries, num, next) = ionian.iterateStreams(streams1and2, 0, MAX);

        assertEq(num, 3);
        assertEq(next, 3);
        assertEq(entries[0].dataRoot, bytes32("root1"));
        assertEq(entries[1].dataRoot, bytes32("root2"));
        assertEq(entries[2].dataRoot, bytes32("root3"));
    }

    function testFewLogs2() public {
        LogEntry[] memory entries;
        uint256 num;
        uint256[] memory next;

        // stream #1
        uint256[] memory from = new uint256[](1);
        from[0] = 0;

        (entries, num, next) = ionian.iterateStreams2(stream1only, from, MAX);

        assertEq(num, 2);
        assertEq(next[0], 2);
        assertEq(entries[0].dataRoot, bytes32("root1"));
        assertEq(entries[1].dataRoot, bytes32("root3"));

        // stream #2
        (entries, num, next) = ionian.iterateStreams2(stream2only, from, MAX);

        assertEq(num, 2);
        assertEq(next[0], 2);
        assertEq(entries[0].dataRoot, bytes32("root2"));
        assertEq(entries[1].dataRoot, bytes32("root3"));

        // streams #1 and #2
        uint256[] memory from2 = new uint256[](2);
        from2[0] = 0;
        from2[1] = 0;

        (entries, num, next) = ionian.iterateStreams2(streams1and2, from2, MAX);

        assertEq(num, 3);
        assertEq(next[0], 2);
        assertEq(next[1], 2);
        assertEq(entries[0].dataRoot, bytes32("root1"));
        assertEq(entries[1].dataRoot, bytes32("root2"));
        assertEq(entries[2].dataRoot, bytes32("root3"));
    }
}

contract LongStreamQueries is BaseSetup {
    uint256 public constant MAX = 1000;

    uint256[] internal from;
    uint256[] internal from2;

    function setUp() public virtual override {
        BaseSetup.setUp();

        // create two streams
        vm.startPrank(alice);
        ionian.createStream(AccessControl(address(0)));
        ionian.createStream(AccessControl(address(0)));
        vm.stopPrank();

        // utilities
        from = new uint256[](1);
        from[0] = 0;

        from2 = new uint256[](2);
        from2[0] = 0;
        from2[1] = 0;
    }
}

contract DenseStreamQueries is LongStreamQueries {
    function setUp() public virtual override {
        LongStreamQueries.setUp();

        // create log
        vm.startPrank(alice);

        for (uint256 ii = 0; ii < MAX; ++ii) {
            if (ii % 3 == 0) {
                ionian.appendLog(stream1only, "one", bytes32("one"));
            } else if (ii % 3 == 1) {
                ionian.appendLog(stream2only, "two", bytes32("two"));
            } else {
                ionian.appendLog(streams1and2, "both", bytes32("both"));
            }
        }

        vm.stopPrank();
    }

    function testDenseLogs1() public {
        uint256 num;

        // stream #1
        (, num, ) = ionian.iterateStreams(stream1only, 0, MAX);
        assertEq(num, 667);

        // stream #2
        (, num, ) = ionian.iterateStreams(stream2only, 0, MAX);
        assertEq(num, 666);

        // stream2 #1 and #2
        (, num, ) = ionian.iterateStreams(streams1and2, 0, MAX);
        assertEq(num, MAX);
    }

    function testDenseLogs2() public {
        uint256 num;

        // stream #1
        (, num, ) = ionian.iterateStreams2(stream1only, from, MAX);
        assertEq(num, 667);

        // stream #2
        (, num, ) = ionian.iterateStreams2(stream2only, from, MAX);
        assertEq(num, 666);

        // streams #1 and #2
        (, num, ) = ionian.iterateStreams2(streams1and2, from2, MAX);
        assertEq(num, MAX);
    }
}

contract SparseStreamQueries is LongStreamQueries {
    function setUp() public virtual override {
        LongStreamQueries.setUp();

        // create log
        vm.startPrank(alice);

        for (uint256 ii = 0; ii < MAX; ++ii) {
            if (ii % 300 == 0) {
                ionian.appendLog(streams1and2, "both", bytes32("both"));
            } else if (ii % 100 == 0) {
                ionian.appendLog(stream1only, "one", bytes32("one"));
            } else if (ii % 150 == 0) {
                ionian.appendLog(stream2only, "two", bytes32("two"));
            } else {
                ionian.appendLog("null", bytes32("null"));
            }
        }

        vm.stopPrank();
    }

    function testSparseLogs1() public {
        uint256 num;

        // stream #1
        (, num, ) = ionian.iterateStreams(stream1only, 0, MAX);
        assertEq(num, 10);

        // stream #2
        (, num, ) = ionian.iterateStreams(stream2only, 0, MAX);
        assertEq(num, 7);

        // stream2 #1 and #2
        (, num, ) = ionian.iterateStreams(streams1and2, 0, MAX);
        assertEq(num, 13);
    }

    function testSparseLogs2() public {
        uint256 num;

        // stream #1
        (, num, ) = ionian.iterateStreams2(stream1only, from, MAX);
        assertEq(num, 10);

        // stream #2
        (, num, ) = ionian.iterateStreams2(stream2only, from, MAX);
        assertEq(num, 7);

        // streams #1 and #2
        (, num, ) = ionian.iterateStreams2(streams1and2, from2, MAX);
        assertEq(num, 13);
    }
}
