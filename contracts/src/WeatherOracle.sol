// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title WeatherOracle
/// @notice Immutable on-chain record of weather events recorded by the authorized agent.
///         Used for auditability — any observer can verify what data triggered a payout.
/// @dev Enhanced: Supports multiple weather APIs for redundancy and consensus.
contract WeatherOracle {
    enum EventType {
        DROUGHT,
        FLOOD,
        EXTREME_HEAT,
        DRY_SPELL
    }

    struct WeatherEvent {
        int256 lat;        // latitude scaled by 1e6
        int256 lng;        // longitude scaled by 1e6
        EventType eventType;
        int256 value;      // consensus value
        uint40 timestamp;
        ApiData[] sources; // multiple data sources
    }

    struct ApiData {
        string source;
        int256 value;
        uint40 timestamp;
    }

    address public immutable agent;

    // eventId => WeatherEvent
    mapping(bytes32 => WeatherEvent) public events;

    // region hash => list of event IDs (region = keccak256(lat, lng, 50km grid))
    mapping(bytes32 => bytes32[]) public regionEvents;

    event WeatherEventRecorded(
        bytes32 indexed eventId,
        bytes32 indexed regionHash,
        EventType eventType,
        int256 value,
        uint40 timestamp
    );

    error Unauthorized();
    error EventAlreadyExists();

    modifier onlyAgent() {
        if (msg.sender != agent) revert Unauthorized();
        _;
    }

    constructor(address _agent) {
        agent = _agent;
    }

    /// @notice Record a weather event with multiple API sources.
    function recordEvent(
        int256 lat,
        int256 lng,
        EventType eventType,
        ApiData[] calldata apiData,
        uint40 timestamp
    ) external onlyAgent returns (bytes32 eventId) {
        eventId = keccak256(abi.encodePacked(lat, lng, eventType, timestamp));

        if (events[eventId].timestamp != 0) revert EventAlreadyExists();

        int256 consensusValue = _calculateConsensus(apiData);

        ApiData[] memory sources = new ApiData[](apiData.length);
        for (uint256 i = 0; i < apiData.length; i++) {
            sources[i] = apiData[i];
        }

        events[eventId] = WeatherEvent({
            lat: lat,
            lng: lng,
            eventType: eventType,
            value: consensusValue,
            timestamp: timestamp,
            sources: sources
        });

        bytes32 regionHash = _regionHash(lat, lng);
        regionEvents[regionHash].push(eventId);

        emit WeatherEventRecorded(eventId, regionHash, eventType, consensusValue, timestamp);
    }

    /// @notice Get a single weather event by ID.
    function getEvent(bytes32 eventId) external view returns (WeatherEvent memory) {
        return events[eventId];
    }

    /// @notice Get all event IDs for a geographic region.
    function getRegionEvents(int256 lat, int256 lng) external view returns (bytes32[] memory) {
        return regionEvents[_regionHash(lat, lng)];
    }

    /// @notice Get events in a time range for a region.
    function getEventsInRange(
        int256 lat,
        int256 lng,
        uint40 from,
        uint40 to
    ) external view returns (WeatherEvent[] memory) {
        bytes32 regionHash = _regionHash(lat, lng);
        bytes32[] memory ids = regionEvents[regionHash];

        // Count matching
        uint256 count;
        for (uint256 i = 0; i < ids.length; i++) {
            WeatherEvent storage e = events[ids[i]];
            if (e.timestamp >= from && e.timestamp <= to) count++;
        }

        WeatherEvent[] memory result = new WeatherEvent[](count);
        uint256 idx;
        for (uint256 i = 0; i < ids.length; i++) {
            WeatherEvent storage e = events[ids[i]];
            if (e.timestamp >= from && e.timestamp <= to) {
                result[idx++] = e;
            }
        }
        return result;
    }

    /// @dev Snap coordinates to a 50km grid for region grouping.
    function _regionHash(int256 lat, int256 lng) internal pure returns (bytes32) {
        // 0.45 degrees ≈ 50km; scale factor 1e6 so 0.45° = 450000
        int256 gridLat = (lat / 450000) * 450000;
        int256 gridLng = (lng / 450000) * 450000;
        return keccak256(abi.encodePacked(gridLat, gridLng));
    }

    /// @dev Calculate consensus value from multiple API data (simple average).
    function _calculateConsensus(ApiData[] calldata apiData) internal pure returns (int256) {
        int256 sum = 0;
        for (uint256 i = 0; i < apiData.length; i++) {
            sum += apiData[i].value;
        }
        return sum / int256(apiData.length);
    }
}
