// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title WeatherOracle
/// @notice Immutable on-chain record of weather events recorded by the authorized agent.
///         Used for auditability — any observer can verify what data triggered a payout.
/// @dev Enhanced: Supports multiple weather APIs for redundancy and consensus. Requires at least 2 sources.
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
        string source;  // API name, e.g., "open-meteo"
        int256 value;   // Data value
        uint40 timestamp; // Data timestamp
    }

    address public immutable agent;

    // Minimum number of API sources required for consensus
    uint256 public constant MIN_SOURCES = 2;

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
        uint40 timestamp,
        uint256 sourceCount
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

    /// @notice Record a weather event with multiple API sources.
    function recordEvent(
        int256 lat,
        int256 lng,
        EventType eventType,
        ApiData[] calldata apiData,
        uint40 timestamp
    ) external onlyAgent returns (bytes32 eventId) {
        require(apiData.length >= MIN_SOURCES, "Insufficient sources");

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

        emit WeatherEventRecorded(eventId, regionHash, eventType, consensusValue, timestamp, apiData.length);
    }

    /// @notice Record raw API data for logging purposes. Called by agent before consensus.
    /// @param source The API source name (e.g., "open-meteo")
    /// @param lat Latitude scaled by 1e6
    /// @param lng Longitude scaled by 1e6
    /// @param temperature Temperature in °C * 100
    /// @param rainfall Rainfall in mm * 100
    /// @param timestamp Unix timestamp
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
    /// @param eventId The event ID this consensus relates to
    /// @param sourcesUsed Number of API sources used in consensus
    /// @param finalTemperature Final consensus temperature
    /// @param finalRainfall Final consensus rainfall
    /// @param timestamp Unix timestamp
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
    /// @param eventId The event ID that triggered the threshold
    /// @param eventType The type of weather event
    /// @param value The measured value that triggered the threshold
    /// @param threshold The threshold value that was breached
    function recordThresholdTrigger(
        bytes32 eventId,
        EventType eventType,
        int256 value,
        int256 threshold
    ) external onlyAgent {
        emit EventThresholdTriggered(eventId, eventType, value, threshold);
    }

    /// @notice Record agent heartbeat for monitoring system health.
    /// @param eventsRecordedToday Number of events recorded in the current day
    function recordHeartbeat(uint256 eventsRecordedToday) external onlyAgent {
        lastHeartbeatTimestamp = block.timestamp;
        eventsToday = eventsRecordedToday;
        emit AgentHeartbeat(uint40(block.timestamp), eventsRecordedToday);
    }

    /// @notice Get comprehensive logging statistics.
    /// @return totalEvents Total events recorded
    /// @return totalApiCalls_ Total API calls made
    /// @return lastHeartbeat Last heartbeat timestamp
    /// @return eventsToday_ Events recorded today
    /// @return totalFailures Total API failures
    /// @return totalAlerts Total system alerts
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

    /// @notice Get the API sources for a weather event.
    function getEventSources(bytes32 eventId) external view returns (ApiData[] memory) {
        return events[eventId].sources;
    }

    /// @notice Check if the consensus is reliable (variance below threshold).
    /// @param eventId The event ID
    /// @param threshold Maximum allowed variance
    /// @return True if variance <= threshold
    function isConsensusReliable(bytes32 eventId, int256 threshold) external view returns (bool) {
        ApiData[] memory sources = events[eventId].sources;
        if (sources.length < 2) return true; // single source is reliable
        int256 mean = events[eventId].value;
        int256 variance = 0;
        for (uint256 i = 0; i < sources.length; i++) {
            int256 diff = sources[i].value - mean;
            variance += diff * diff;
        }
        variance /= int256(sources.length);
        return variance <= threshold;
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
        uint256 length = ids.length;

        // Count matching
        uint256 count;
        for (uint256 i = 0; i < length; ) {
            WeatherEvent storage e = events[ids[i]];
            if (e.timestamp >= from && e.timestamp <= to) count++;
            unchecked { i++; }
        }

        WeatherEvent[] memory result = new WeatherEvent[](count);
        uint256 idx;
        for (uint256 i = 0; i < length; ) {
            WeatherEvent storage e = events[ids[i]];
            if (e.timestamp >= from && e.timestamp <= to) {
                result[idx] = e;
                unchecked { idx++; }
            }
            unchecked { i++; }
        }
        return result;
    }

    /// @dev Snap coordinates to a 50km grid for region grouping.
    function _regionHash(int256 lat, int256 lng) internal pure returns (bytes32) {
        // 0.45 degrees ≈ 50km; scale factor 1e6 so 0.45° = 450000
        int256 gridLat;
        int256 gridLng;
        assembly {
            gridLat := mul(sdiv(lat, 450000), 450000)
            gridLng := mul(sdiv(lng, 450000), 450000)
        }
        return keccak256(abi.encodePacked(gridLat, gridLng));
    }

    /// @dev Calculate consensus value from multiple API data (simple average).
    /// @param apiData Array of API data points
    /// @return The average value
    function _calculateConsensus(ApiData[] calldata apiData) internal pure returns (int256) {
        int256 sum = 0;
        for (uint256 i = 0; i < apiData.length; i++) {
            sum += apiData[i].value;
        }
        return sum / int256(apiData.length);
    }
}
