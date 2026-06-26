import Foundation

/// Chart spec with data embedded directly (no refetch on render). Built by the
/// `prepare_chart` tool in Swift and copied verbatim into `CoachResponse.chart`
/// by the model  -  ports `CoachChartSpec` from the web app.
struct CoachChart: Codable, Equatable {
    var chartType: CoachChartType
    var title: String
    var metric: CoachChartMetric
    var range: CoachChartRange
    var data: [CoachChartPoint]
    var annotations: [CoachChartAnnotation]

    enum CodingKeys: String, CodingKey {
        case chartType = "chart_type"
        case title, metric, range, data, annotations
    }

    init(
        chartType: CoachChartType,
        title: String,
        metric: CoachChartMetric,
        range: CoachChartRange,
        data: [CoachChartPoint] = [],
        annotations: [CoachChartAnnotation] = []
    ) {
        self.chartType = chartType
        self.title = title
        self.metric = metric
        self.range = range
        self.data = data
        self.annotations = annotations
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chartType = try c.decode(CoachChartType.self, forKey: .chartType)
        title = try c.decode(String.self, forKey: .title)
        metric = try c.decode(CoachChartMetric.self, forKey: .metric)
        range = try c.decode(CoachChartRange.self, forKey: .range)
        data = try c.decodeIfPresent([CoachChartPoint].self, forKey: .data) ?? []
        annotations = try c.decodeIfPresent([CoachChartAnnotation].self, forKey: .annotations) ?? []
    }
}

enum CoachChartType: String, Codable {
    case line, bar, dot, sleepStage = "sleep_stage", sparkline
}

enum CoachChartMetric: String, Codable {
    case steps, hr, spo2, sleep, activeMinutes = "active_minutes", calories, distance
}

struct CoachChartRange: Codable, Equatable {
    var start: String
    var end: String
}

/// One plotted point. `series` categorizes multi-series data (e.g. sleep-stage
/// name); nil for single-series charts.
struct CoachChartPoint: Codable, Equatable, Identifiable {
    var x: String
    var y: Double
    var series: String?
    var id: String { x + (series ?? "") }
}

struct CoachChartAnnotation: Codable, Equatable, Identifiable {
    var x: String
    var label: String
    var id: String { x + label }
}
