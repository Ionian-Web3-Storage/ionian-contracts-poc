// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {DSTest} from "ds-test/test.sol";
import {Utilities} from "./utils/Utilities.sol";
import {console} from "./utils/Console.sol";
import {Vm} from "forge-std/Vm.sol";

import {IonianLog, AccessControl, IonianStructs, IonianEvents, IonianErrors} from "../IonianLog.sol";

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

contract BaseSetup is DSTest, IonianStructs, IonianEvents, IonianErrors {
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

        ionian.appendLog(bytes32("root1"), 32);
        ionian.appendLogWithData("data1");

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
        ionian.appendLog(bytes32("root1"), 32, stream1only);
        vm.stopPrank();

        // new stream by Bob
        vm.startPrank(bob);
        SimpleAccessControl ac = new SimpleAccessControl();
        ionian.createStream(ac);
        ionian.appendLog(bytes32("root2"), 32, stream2only);
        vm.stopPrank();

        // access denied
        vm.startPrank(alice);
        vm.expectRevert(Unauthorized.selector);
        ionian.appendLog(bytes32("root3"), 32, streams1and2);
        vm.stopPrank();

        // grant access
        vm.prank(bob);
        ac.approve(alice);

        vm.prank(alice);
        ionian.appendLog(bytes32("root3"), 32, streams1and2);

        LogEntry[] memory entries = ionian.getLogEntries(0, 100);
        assertEq(entries.length, 3);
        assertEq(entries[0].dataRoot, bytes32("root1"));
        assertEq(entries[1].dataRoot, bytes32("root2"));
        assertEq(entries[2].dataRoot, bytes32("root3"));
    }
}
