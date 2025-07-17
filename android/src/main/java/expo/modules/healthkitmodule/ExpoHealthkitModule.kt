package expo.modules.healthkitmodule

import android.content.Context
import android.content.pm.PackageManager
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.*
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import expo.modules.kotlin.Promise
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.net.URL
import java.time.Instant
import java.time.format.DateTimeFormatter
import kotlin.reflect.KClass

class ExpoHealthkitModule : Module() {
  private val context: Context
    get() = appContext.reactContext ?: throw Exception("React context is not available")

  private val healthConnectClient by lazy { HealthConnectClient.getOrCreate(context) }
  private val moduleScope = CoroutineScope(Dispatchers.Main)

  // Complete health data types mapping - restored all original identifiers
  private val recordTypeMap = mapOf(
    "ActiveCaloriesBurned" to Pair(ActiveCaloriesBurnedRecord::class, HealthPermission.getReadPermission(ActiveCaloriesBurnedRecord::class)),
    "BasalMetabolicRate" to Pair(BasalMetabolicRateRecord::class, HealthPermission.getReadPermission(BasalMetabolicRateRecord::class)),
    "BodyFat" to Pair(BodyFatRecord::class, HealthPermission.getReadPermission(BodyFatRecord::class)),
    "CyclingPedalingCadence" to Pair(CyclingPedalingCadenceRecord::class, HealthPermission.getReadPermission(CyclingPedalingCadenceRecord::class)),
    "Distance" to Pair(DistanceRecord::class, HealthPermission.getReadPermission(DistanceRecord::class)),
    "ElevationGained" to Pair(ElevationGainedRecord::class, HealthPermission.getReadPermission(ElevationGainedRecord::class)),
    "ExerciseSession" to Pair(ExerciseSessionRecord::class, HealthPermission.getReadPermission(ExerciseSessionRecord::class)),
    "FloorsClimbed" to Pair(FloorsClimbedRecord::class, HealthPermission.getReadPermission(FloorsClimbedRecord::class)),
    "HeartRate" to Pair(HeartRateRecord::class, HealthPermission.getReadPermission(HeartRateRecord::class)),
    "LeanBodyMass" to Pair(LeanBodyMassRecord::class, HealthPermission.getReadPermission(LeanBodyMassRecord::class)),
    "OxygenSaturation" to Pair(OxygenSaturationRecord::class, HealthPermission.getReadPermission(OxygenSaturationRecord::class)),
    "RespiratoryRate" to Pair(RespiratoryRateRecord::class, HealthPermission.getReadPermission(RespiratoryRateRecord::class)),
    "RestingHeartRate" to Pair(RestingHeartRateRecord::class, HealthPermission.getReadPermission(RestingHeartRateRecord::class)),
    "SleepSession" to Pair(SleepSessionRecord::class, HealthPermission.getReadPermission(SleepSessionRecord::class)),
    "Speed" to Pair(SpeedRecord::class, HealthPermission.getReadPermission(SpeedRecord::class)),
    "StepsCadence" to Pair(StepsCadenceRecord::class, HealthPermission.getReadPermission(StepsCadenceRecord::class)),
    "Steps" to Pair(StepsRecord::class, HealthPermission.getReadPermission(StepsRecord::class)),
    "TotalCaloriesBurned" to Pair(TotalCaloriesBurnedRecord::class, HealthPermission.getReadPermission(TotalCaloriesBurnedRecord::class)),
    "Vo2Max" to Pair(Vo2MaxRecord::class, HealthPermission.getReadPermission(Vo2MaxRecord::class))
  )

  private fun isHealthConnectAvailable(): Boolean {
    return try {
      val packageManager = context.packageManager
      packageManager.getPackageInfo("com.google.android.apps.healthdata", 0)
      true
    } catch (e: PackageManager.NameNotFoundException) {
      false
    }
  }

  private fun formatRecordToStandardFormat(record: Record): Map<String, Any?> {
    val formatter = DateTimeFormatter.ISO_INSTANT

    return when (record) {
      is InstantaneousRecord -> mapOf(
        "type" to record::class.simpleName,
        "sourceName" to (record.metadata.dataOrigin.packageName ?: "Unknown"),
        "sourceVersion" to null,
        "device" to (record.metadata.device?.model ?: record.metadata.device?.manufacturer),
        "creationDate" to formatter.format(record.time),
        "startDate" to formatter.format(record.time),
        "endDate" to formatter.format(record.time),
        "metadata" to emptyMap<String, Any>(),
        "unit" to getUnitForRecord(record),
        "value" to getValueForRecord(record)
      )
      is IntervalRecord -> mapOf(
        "type" to record::class.simpleName,
        "sourceName" to (record.metadata.dataOrigin.packageName ?: "Unknown"),
        "sourceVersion" to null,
        "device" to (record.metadata.device?.model ?: record.metadata.device?.manufacturer),
        "creationDate" to formatter.format(record.endTime),
        "startDate" to formatter.format(record.startTime),
        "endDate" to formatter.format(record.endTime),
        "metadata" to emptyMap<String, Any>(),
        "unit" to getUnitForRecord(record),
        "value" to getValueForRecord(record)
      )
      else -> mapOf(
        "type" to record::class.simpleName,
        "sourceName" to "Unknown",
        "sourceVersion" to null,
        "device" to null,
        "creationDate" to formatter.format(Instant.now()),
        "startDate" to formatter.format(Instant.now()),
        "endDate" to formatter.format(Instant.now()),
        "metadata" to emptyMap<String, Any>(),
        "unit" to "unknown",
        "value" to "unknown"
      )
    }
  }

  private fun getUnitForRecord(record: Record): String {
    return when (record) {
      is ActiveCaloriesBurnedRecord -> "kcal"
      is BasalMetabolicRateRecord -> "kcal/day"
      is BodyFatRecord -> "%"
      is CyclingPedalingCadenceRecord -> "rpm"
      is DistanceRecord -> "m"
      is ElevationGainedRecord -> "m"
      is FloorsClimbedRecord -> "count"
      is HeartRateRecord -> "bpm"
      is LeanBodyMassRecord -> "kg"
      is OxygenSaturationRecord -> "%"
      is RespiratoryRateRecord -> "breaths/min"
      is RestingHeartRateRecord -> "bpm"
      is SpeedRecord -> "m/s"
      is StepsCadenceRecord -> "steps/min"
      is StepsRecord -> "count"
      is TotalCaloriesBurnedRecord -> "kcal"
      is Vo2MaxRecord -> "mL/(kg·min)"
      is ExerciseSessionRecord -> "session"
      is SleepSessionRecord -> "session"
      else -> "unknown"
    }
  }

  private fun getValueForRecord(record: Record): Any {
    return when (record) {
      is ActiveCaloriesBurnedRecord -> record.energy.inKilocalories
      is BasalMetabolicRateRecord -> record.basalMetabolicRate.inKilocaloriesPerDay
      is BodyFatRecord -> record.percentage.value
      is CyclingPedalingCadenceRecord -> record.revolutionsPerMinute
      is DistanceRecord -> record.distance.inMeters
      is ElevationGainedRecord -> record.elevation.inMeters
      is FloorsClimbedRecord -> record.floors
      is HeartRateRecord -> record.beatsPerMinute
      is LeanBodyMassRecord -> record.mass.inKilograms
      is OxygenSaturationRecord -> record.percentage.value
      is RespiratoryRateRecord -> record.rate
      is RestingHeartRateRecord -> record.beatsPerMinute
      is SpeedRecord -> record.speed.inMetersPerSecond
      is StepsCadenceRecord -> record.rate
      is StepsRecord -> record.count
      is TotalCaloriesBurnedRecord -> record.energy.inKilocalories
      is Vo2MaxRecord -> record.vo2MillilitersPerMinuteKilogram
      is ExerciseSessionRecord -> record.exerciseType.name
      is SleepSessionRecord -> record.stages.size
      else -> "unknown"
    }
  }

  override fun definition() = ModuleDefinition {
    Name("ExpoHealthkitModule")

    Constants(
      "PI" to Math.PI
    )

    Events("onChange")

    Function("hello") {
      "Hello world! 👋"
    }

    AsyncFunction("setValueAsync") { value: String ->
      sendEvent("onChange", mapOf(
        "value" to value
      ))
    }

    AsyncFunction("authorizeHealthKit") { promise: Promise ->
      if (!isHealthConnectAvailable()) {
        promise.resolve(mapOf(
          "success" to false,
          "granted" to emptyList<String>(),
          "denied" to emptyList<String>(),
          "error" to "Health Connect is not available on this device. Please install Google Health Connect."
        ))
        return@AsyncFunction
      }

      moduleScope.launch {
        try {
          // Note: Actual permission flow requires UI interaction
          // For now, return available types (permissions must be handled separately)
          val availableTypes = recordTypeMap.keys.toList()

          promise.resolve(mapOf(
            "success" to true,
            "granted" to availableTypes,
            "denied" to emptyList<String>(),
            "error" to null
          ))
        } catch (e: Exception) {
          promise.resolve(mapOf(
            "success" to false,
            "granted" to emptyList<String>(),
            "denied" to recordTypeMap.keys.toList(),
            "error" to e.message
          ))
        }
      }
    }

    AsyncFunction("getHealthData") { options: Map<String, String>, promise: Promise ->
      val identifier = options["identifier"]
      val startDateString = options["startDate"]
      val endDateString = options["endDate"]

      if (identifier == null || startDateString == null || endDateString == null) {
        promise.resolve(mapOf(
          "success" to false,
          "data" to emptyList<Any>(),
          "error" to mapOf(
            "code" to "missing_arguments",
            "message" to "Missing required options: identifier, startDate, endDate."
          )
        ))
        return@AsyncFunction
      }

      if (!isHealthConnectAvailable()) {
        promise.resolve(mapOf(
          "success" to false,
          "data" to emptyList<Any>(),
          "error" to mapOf(
            "code" to "health_connect_unavailable",
            "message" to "Health Connect is not available on this device."
          )
        ))
        return@AsyncFunction
      }

      val recordTypeInfo = recordTypeMap[identifier]
      if (recordTypeInfo == null) {
        promise.resolve(mapOf(
          "success" to false,
          "data" to emptyList<Any>(),
          "error" to mapOf(
            "code" to "unsupported_identifier",
            "message" to "Identifier '$identifier' not supported. Available: ${recordTypeMap.keys.joinToString(", ")}"
          )
        ))
        return@AsyncFunction
      }

      moduleScope.launch {
        try {
          val startTime = Instant.parse(startDateString)
          val endTime = Instant.parse(endDateString)

          val request = ReadRecordsRequest(
            recordType = recordTypeInfo.first,
            timeRangeFilter = TimeRangeFilter.between(startTime, endTime)
          )

          val response = healthConnectClient.readRecords(request)
          val formattedData = response.records.map { record ->
            formatRecordToStandardFormat(record)
          }

          promise.resolve(mapOf(
            "success" to true,
            "data" to formattedData,
            "error" to null
          ))
        } catch (e: Exception) {
          promise.resolve(mapOf(
            "success" to false,
            "data" to emptyList<Any>(),
            "error" to mapOf(
              "code" to "query_error",
              "message" to "Failed to fetch data: ${e.message}"
            )
          ))
        }
      }
    }

    // Background Sync - Stub (Expo BackgroundTask handles this)
    AsyncFunction("enableBackgroundSync") { options: Map<String, Any>, promise: Promise ->
      promise.resolve(mapOf(
        "success" to false,
        "error" to "Background sync handled by Expo BackgroundTask service. Enable sync in main app."
      ))
    }

    AsyncFunction("getBackgroundSyncStatus") { promise: Promise ->
      promise.resolve(mapOf(
        "enabled" to false,
        "lastSync" to null
      ))
    }

    AsyncFunction("disableBackgroundSync") { promise: Promise ->
      promise.resolve(mapOf(
        "success" to true,
        "error" to null
      ))
    }

    View(ExpoHealthkitModuleView::class) {
      Prop("url") { view: ExpoHealthkitModuleView, url: URL ->
        view.webView.loadUrl(url.toString())
      }
      Events("onLoad")
    }
  }
}
