//
// Created by Matt Greenfield on 5/07/17.
// Copyright (c) 2017 Big Paua. All rights reserved.
//

import CoreLocation
import ArcKitCore

/**
 A composite, high level representation of the device's location, motion, and activity states over a brief
 duration of time.
 
 The current sample can be retrieved from `LocomotionManager.highlander.locomotionSample()`.
 
 ## Dynamic Sample Sizes
 
 Each sample's duration is dynamically determined, depending on the quality and quantity of available ocation
 and motion data. Samples sizes typically range from 10 to 60 seconds, however varying conditions can sometimes
 produce sample durations outside those bounds.
 
 Higher quality and quantity of available data results in shorter sample durations, with more specific
 representations of single moments in time.
 
 Lesser quality or quantity of available data result in longer sample durations, thus representing the average or most
 common states and location over the sample period instead of a single specific moment.
 */
public class LocomotionSample: ActivityTypeClassifiable {

    private(set) public var sampleId: UUID

    /// The timestamp for the weighted centre of the sample period. Equivalent to `location.timestamp`.
    public let date: Date
    
    // MARK: Location Properties

    /** 
     The sample's smoothed location, equivalent to the weighted centre of the sample's `filteredLocations`.
     
     This is the most high level location value, representing the final result of all available filtering and smoothing
     algorithms. This value is most useful for drawing smooth, coherent paths on a map for end user consumption.
     */
    public let location: CLLocation?
    
    /**
     The raw locations received over the sample duration.
     */
    public let rawLocations: [CLLocation]
    
    /**
     The Kalman filtered locations recorded over the sample duration.
     */
    public let filteredLocations: [CLLocation]
    
    /// The moving or stationary state for the sample. See `MovingState` for details on possible values.
    public let movingState: MovingState

    // The recording state of the LocomotionManager at the time the sample was taken.
    public let recordingState: RecordingState
    
    // MARK: Motion Properties
    
    /** 
     The user's walking/running/cycling cadence (steps per second) over the sample duration.
     
     This value is taken from [CMPedometer](https://developer.apple.com/documentation/coremotion/cmpedometer). and will
     only contain a usable value if `startCoreMotion()` has been called on the LocomotionManager.
     
     - Note: If the user is travelling by vehicle, this value may report a false value due to bumpy motion being 
     misinterpreted as steps by CMPedometer.
     */
    public let stepHz: Double?
    
    /** 
     The degree of variance in course direction over the sample duration.
     
     A value of 0.0 represents a perfectly straight path. A value of 1.0 represents complete inconsistency of 
     direction between each location.
     
     This value may indicate several different conditions, such as high or low location accuracy (ie clean or erratic
     paths due to noisy location data), or the user travelling in either a straight or curved path. However given that 
     the filtered locations already have the majority of path jitter removed, this value should not be considered in
     isolation from other factors - no firm conclusions can be drawn from it alone.
     */
    public let courseVariance: Double?
    
    /**
     The average amount of accelerometer motion on the XY plane over the sample duration.
     
     This value can be taken to be `mean(abs(xyAccelerations)) + (std(abs(xyAccelerations) * 3.0)`, with 
     xyAccelerations being the recorded accelerometer X and Y values over the sample duration. Thus it represents the
     mean + 3SD of the unsigned acceleration values.
     */
    public let xyAcceleration: Double?
    
    /**
     The average amount of accelerometer motion on the Z axis over the sample duration.
     
     This value can be taken to be `mean(abs(zAccelerations)) + (std(abs(zAccelerations) * 3.0)`, with
     zAccelerations being the recorded accelerometer Z values over the sample duration. Thus it represents the
     mean + 3SD of the unsigned acceleration values.
     */
    public let zAcceleration: Double?
    
    // MARK: Activity Type Properties
    
    /**
     The highest scoring Core Motion activity type 
     ([CMMotionActivity](https://developer.apple.com/documentation/coremotion/cmmotionactivity)) at the time of the 
     sample's `date`.
     */
    public let coreMotionActivityType: CoreMotionActivityTypeName?

    // MARK: References

    /**
     The sample's parent `TimelineItem`, if recording is being done via `TimelineManager`.

     - Note: If recording is being done directly with `LocomotionManager`, this value will be nil.
     */
    public weak var timelineItem: TimelineItem?

    internal(set) public var classifierResults: ClassifierResults?

    public var activityType: ActivityTypeName? {
        return classifierResults?.first?.name
    }

    // MARK: Convenience Getters
    
    /// A convenience getter for the sample's time interval since start of day.
    public lazy var timeOfDay: TimeInterval = {
        return self.date.sinceStartOfDay
    }()

    public var hasUsableCoordinate: Bool {
        return location?.hasUsableCoordinate ?? false
    }

    public func distance(from otherSample: LocomotionSample) -> CLLocationDistance? {
        guard let myLocation = location, let theirLocation = otherSample.location else {
            return nil
        }
        return myLocation.distance(from: theirLocation)
    }
    
    internal init(sample: ActivityBrainSample) {
        self.sampleId = UUID()

        if let location = sample.location  {
            self.rawLocations = sample.rawLocations
            self.filteredLocations = sample.filteredLocations
            self.location = CLLocation(coordinate: location.coordinate, altitude: location.altitude,
                                       horizontalAccuracy: location.horizontalAccuracy,
                                       verticalAccuracy: location.verticalAccuracy, course: sample.course,
                                       speed: sample.speed, timestamp: location.timestamp)
            self.date = location.timestamp
            
        } else {
            self.filteredLocations = []
            self.rawLocations = []
            self.location = nil
            self.date = Date()
        }

        self.recordingState = LocomotionManager.highlander.recordingState
        
        self.movingState = sample.movingState
        self.courseVariance = sample.courseVariance
        self.xyAcceleration = sample.xyAcceleration
        self.zAcceleration = sample.zAcceleration
        self.stepHz = sample.stepHz
        
        self.coreMotionActivityType = sample.coreMotionActivityType
    }
}

extension LocomotionSample: CustomStringConvertible {
    public var description: String {
        let seconds = filteredLocations.dateInterval?.duration ?? 0
        let locationsN = filteredLocations.count
        let locationsHz = locationsN > 0 && seconds > 0 ? Double(locationsN) / seconds : 0.0
        return String(format: "\(locationsN) locations (%.1f Hz), \(String(duration: seconds))", locationsHz)
    }
}

extension LocomotionSample: Hashable {
    public var hashValue: Int {
        return sampleId.hashValue
    }
    public static func ==(lhs: LocomotionSample, rhs: LocomotionSample) -> Bool {
        return lhs.sampleId == rhs.sampleId
    }
}

public extension Array where Element: LocomotionSample {

    public var center: CLLocation? {
        return CLLocation(centerFor: self)
    }

    public var weightedCenter: CLLocation? {
        return CLLocation(weightedCenterFor: self)
    }

    public var duration: TimeInterval {
        guard let firstDate = first?.date, let lastDate = last?.date else {
            return 0
        }
        return lastDate.timeIntervalSince(firstDate)
    }

    public var distance: CLLocationDistance {
        return flatMap { $0.location }.distance
    }

    func radiusFrom(center: CLLocation) -> (mean: CLLocationDistance, sd: CLLocationDistance) {
        return flatMap { $0.location }.radiusFrom(center: center)
    }

    public var weightedMeanAltitude: CLLocationDistance? {
        return flatMap { $0.location }.weightedMeanAltitude
    }

    public var horizontalAccuracyRange: AccuracyRange? {
        return flatMap { $0.location }.horizontalAccuracyRange
    }

    public var verticalAccuracyRange: AccuracyRange? {
        return flatMap { $0.location }.verticalAccuracyRange
    }
    
}
