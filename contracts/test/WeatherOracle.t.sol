// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {WeatherOracle} from "../src/WeatherOracle.sol";

contract WeatherOracleTest is Test {
    WeatherOracle public oracle;

    address public agent = makeAddr("agent");
    address public other = makeAddr("other");

    int256 constant LAT = -1292100; // Nairobi
    int256 constant LNG = 36821800;

    function setUp() public {
        oracle = new WeatherOracle(agent);
    }

    function test_RecordEvent() public {
        vm.prank(agent);
        bytes32 eventId = oracle.recordEvent(
            LAT, LNG,
            WeatherOracle.EventType.DROUGHT,
            1500,
            uint40(block.timestamp),
            "open-meteo"
        );

        WeatherOracle.WeatherEvent memory e = oracle.getEvent(eventId);
        assertEq(e.lat, LAT);
        assertEq(e.lng, LNG);
        assertEq(uint8(e.eventType), uint8(WeatherOracle.EventType.DROUGHT));
        assertEq(e.value, 1500);
        assertEq(e.timestamp, uint40(block.timestamp));
    }

    function test_OnlyAgentCanRecord() public {
        vm.expectRevert(WeatherOracle.Unauthorized.selector);
        vm.prank(other);
        oracle.recordEvent(LAT, LNG, WeatherOracle.EventType.FLOOD, 2000, uint40(block.timestamp), "open-meteo");
    }

    function test_CannotRecordDuplicateEvent() public {
        vm.prank(agent);
        oracle.recordEvent(LAT, LNG, WeatherOracle.EventType.DROUGHT, 1500, uint40(block.timestamp), "open-meteo");

        vm.expectRevert(WeatherOracle.EventAlreadyExists.selector);
        vm.prank(agent);
        oracle.recordEvent(LAT, LNG, WeatherOracle.EventType.DROUGHT, 1500, uint40(block.timestamp), "open-meteo");
    }

    function test_GetRegionEvents() public {
        vm.startPrank(agent);
        oracle.recordEvent(LAT, LNG, WeatherOracle.EventType.DROUGHT, 1500, uint40(block.timestamp), "open-meteo");
        oracle.recordEvent(LAT, LNG, WeatherOracle.EventType.FLOOD, 20000, uint40(block.timestamp + 1 days), "nasa-power");
        vm.stopPrank();

        bytes32[] memory events = oracle.getRegionEvents(LAT, LNG);
        assertEq(events.length, 2);
    }

    function test_GetEventsInRange() public {
        uint40 t1 = uint40(block.timestamp);
        uint40 t2 = uint40(block.timestamp + 5 days);
        uint40 t3 = uint40(block.timestamp + 20 days);

        vm.startPrank(agent);
        oracle.recordEvent(LAT, LNG, WeatherOracle.EventType.DROUGHT, 1000, t1, "open-meteo");
        oracle.recordEvent(LAT, LNG, WeatherOracle.EventType.FLOOD, 2000, t2, "open-meteo");
        oracle.recordEvent(LAT, LNG, WeatherOracle.EventType.EXTREME_HEAT, 3800, t3, "nasa-power");
        vm.stopPrank();

        // Query only first two
        WeatherOracle.WeatherEvent[] memory result = oracle.getEventsInRange(
            LAT, LNG, t1, uint40(block.timestamp + 10 days)
        );
        assertEq(result.length, 2);
    }

    function test_NearbyCoordinatesSameRegion() public {
        // Two farms within 50km of each other should share the same region bucket
        int256 nearbyLat = LAT + 100000; // ~11km away
        int256 nearbyLng = LNG + 100000;

        vm.startPrank(agent);
        oracle.recordEvent(LAT, LNG, WeatherOracle.EventType.DROUGHT, 1000, uint40(block.timestamp), "open-meteo");
        oracle.recordEvent(nearbyLat, nearbyLng, WeatherOracle.EventType.DROUGHT, 900, uint40(block.timestamp + 1), "open-meteo");
        vm.stopPrank();

        bytes32[] memory events1 = oracle.getRegionEvents(LAT, LNG);
        bytes32[] memory events2 = oracle.getRegionEvents(nearbyLat, nearbyLng);

        // Both should be in the same region bucket
        assertEq(events1.length, events2.length);
    }

    function test_DistantCoordinatesDifferentRegions() public {
        int256 lagosLat = 6452200;
        int256 lagosLng = 3395800;

        vm.startPrank(agent);
        oracle.recordEvent(LAT, LNG, WeatherOracle.EventType.DROUGHT, 1000, uint40(block.timestamp), "open-meteo");
        oracle.recordEvent(lagosLat, lagosLng, WeatherOracle.EventType.FLOOD, 2000, uint40(block.timestamp + 1), "open-meteo");
        vm.stopPrank();

        bytes32[] memory nairobiEvents = oracle.getRegionEvents(LAT, LNG);
        bytes32[] memory lagosEvents   = oracle.getRegionEvents(lagosLat, lagosLng);

        assertEq(nairobiEvents.length, 1);
        assertEq(lagosEvents.length, 1);
    }
}
