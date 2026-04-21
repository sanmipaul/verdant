// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title WeatherOracle
/// @notice Immutable on-chain record of weather events recorded by the authorized agent.
///         Used for auditability — any observer can verify what data triggered a payout.
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
        int256 value;      // e.g. rainfall in mm * 100, temperature in °C * 100
        uint40 timestamp;
        string dataSource; // "open-meteo" | "nasa-power" | "ai-adjudicated"
    }

    address public immutable agent;

    // eventId => WeatherEvent
    mapping(bytes32 => WeatherEvent) public events;

    // region hash => list of event IDs (region = keccak256(lat, lng, 50km grid))
    mapping(bytes32 => bytes32[]) public regionEvents;

    // Logging statistics
    uint256 public totalEventsRecorded;
    uint256 public totalApiCalls;
    uint256 public lastHeartbeatTimestamp;
    uint256 public eventsToday;
    uint256 public totalApiFailures;
    uint256 public totalSystemAlerts;

    event WeatherEventRecorded(
        bytes32 indexed eventId,
        bytes32 indexed regionHash,
        EventType eventType,
        int256 value,
        uint40 timestamp
    );

    event ApiDataReceived(
        string indexed source,
        int256 lat,
        int256 lng,
        int256 temperature,
        int256 rainfall,
        uint40 timestamp
    );

    event ConsensusCalculated(
        bytes32 indexed eventId,
        uint256 sourcesUsed,
        int256 finalTemperature,
        int256 finalRainfall,
        uint40 timestamp
    );

    event EventThresholdTriggered(
        bytes32 indexed eventId,
        EventType eventType,
        int256 value,
        int256 threshold
    );

    event AgentHeartbeat(
        uint40 timestamp,
        uint256 eventsRecordedToday
    );

    event ApiFailure(
        string indexed source,
        int256 lat,
        int256 lng,
        string reason,
        uint40 timestamp
    );

    event SystemAlert(
        string alertType,
        string message,
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

    /// @notice Record a weather event. Called by the Cloudflare agent after polling APIs.
    function recordEvent(
        int256 lat,
        int256 lng,
        EventType eventType,
        int256 value,
        uint40 timestamp,
        string calldata dataSource
    ) external onlyAgent returns (bytes32 eventId) {
        eventId = keccak256(abi.encodePacked(lat, lng, eventType, timestamp));

        if (events[eventId].timestamp != 0) revert EventAlreadyExists();

        events[eventId] = WeatherEvent({
            lat: lat,
            lng: lng,
            eventType: eventType,
            value: value,
            timestamp: timestamp,
            dataSource: dataSource
        });

        bytes32 regionHash = _regionHash(lat, lng);
        regionEvents[regionHash].push(eventId);

        totalEventsRecorded++;
        eventsToday++;

        emit WeatherEventRecorded(eventId, regionHash, eventType, value, timestamp);
    }

    /// @notice Record raw API data for logging purposes. Called by agent before consensus.
    function recordApiData(
        string calldata source,
        int256 lat,
        int256 lng,
        int256 temperature,
        int256 rainfall,
        uint40 timestamp
    ) external onlyAgent {
        totalApiCalls++;
        emit ApiDataReceived(source, lat, lng, temperature, rainfall, timestamp);
    }

    /// @notice Record consensus calculation results for transparency.
    function recordConsensus(
        bytes32 eventId,
        uint256 sourcesUsed,
        int256 finalTemperature,
        int256 finalRainfall,
        uint40 timestamp
    ) external onlyAgent {
        emit ConsensusCalculated(eventId, sourcesUsed, finalTemperature, finalRainfall, timestamp);
    }

    /// @notice Record when a weather threshold is triggered for an event.
    function recordThresholdTrigger(
        bytes32 eventId,
        EventType eventType,
        int256 value,
        int256 threshold
    ) external onlyAgent {
        emit EventThresholdTriggered(eventId, eventType, value, threshold);
    }

    /// @notice Record agent heartbeat for monitoring system health.
    function recordHeartbeat(uint256 eventsRecordedToday) external onlyAgent {
        lastHeartbeatTimestamp = block.timestamp;
        eventsToday = eventsRecordedToday;
        emit AgentHeartbeat(uint40(block.timestamp), eventsRecordedToday);
    }

    /// @notice Get comprehensive logging statistics.
    function getLoggingStats() external view returns (
        uint256 totalEvents,
        uint256 totalApiCalls_,
        uint256 lastHeartbeat,
        uint256 eventsToday_,
        uint256 totalFailures,
        uint256 totalAlerts
    ) {
        return (totalEventsRecorded, totalApiCalls, lastHeartbeatTimestamp, eventsToday, totalApiFailures, totalSystemAlerts);
    }

    /// @notice Record API failure for monitoring.
    function recordApiFailure(
        string calldata source,
        int256 lat,
        int256 lng,
        string calldata reason
    ) external onlyAgent {
        totalApiFailures++;
        emit ApiFailure(source, lat, lng, reason, uint40(block.timestamp));
    }

    /// @notice Record system alert for critical issues.
    function recordSystemAlert(
        string calldata alertType,
        string calldata message
    ) external onlyAgent {
        totalSystemAlerts++;
        emit SystemAlert(alertType, message, uint40(block.timestamp));
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
}
