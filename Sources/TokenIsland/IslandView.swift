import SwiftUI
import Charts
import TokenIslandCore

private let mint = Color(red: 0.48, green: 0.91, blue: 0.76)
private let secondaryInk = Color.white.opacity(0.46)

struct IslandView: View {
    @ObservedObject var store: IslandStore
    var forExport = false

    var body: some View {
        VStack(spacing: 0) {
            compactHeader
                .frame(width: store.expanded ? store.expandedWidth : store.compactWidth)
                VStack(alignment: .leading, spacing: 0) {
                    brandHeader.padding(.bottom, 23)
                    if store.snapshot != nil {
                        if forExport { dashboard }
                        else { ScrollView(.vertical) { dashboard.padding(.bottom, 4) }.scrollIndicators(.hidden) }
                    }
                    else { connectionState }
                    Spacer(minLength: 8)
                    footer
                }
                .padding(.horizontal, 26)
                .padding(.top, 17)
                .padding(.bottom, 20)
                .frame(width: store.expandedWidth, height: store.detailHeight)
                .transaction { $0.animation = nil }
                .opacity(store.expanded ? 1 : 0)
                .allowsHitTesting(store.expanded)
                .accessibilityHidden(!store.expanded)
        }
        .frame(width: store.expandedWidth, height: store.expandedHeight, alignment: .top)
        .background(Color.black)
        .overlay(alignment: .bottom) {
            Capsule().fill(.white.opacity(0.18)).frame(width: 32, height: 3).padding(.bottom, 7)
                .opacity(store.expanded ? 1 : 0)
        }
        .mask(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: store.expanded ? 28 : 17,
                                   bottomTrailingRadius: store.expanded ? 28 : 17, topTrailingRadius: 0)
                .frame(width: store.expanded ? store.expandedWidth : store.compactWidth,
                       height: store.expanded ? store.expandedHeight : store.headerHeight)
        }
        .foregroundStyle(.white)
        .font(.system(size: 12))
        .preferredColorScheme(.dark)
    }

    private var compactHeader: some View {
        Button(action: store.toggleExpanded) {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: store.signedOut ? "person.crop.circle.badge.exclamationmark" : store.usageScope == .account ? "cloud" : "desktopcomputer")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(mint)
                Text(store.signedOut ? "请登录" : store.compactTokenText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
            }.frame(maxWidth: .infinity)
            if store.notchWidth > 0 { Color.clear.frame(width: store.notchWidth) }
            else { Capsule().fill(.white.opacity(0.18)).frame(width: 1, height: 12).padding(.horizontal, 15) }
            HStack(spacing: 5) {
                Circle().trim(from: 0, to: CGFloat((store.quota?.remaining ?? 0) / 100))
                    .stroke(mint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90)).frame(width: 10, height: 10)
                    .background(Circle().stroke(.white.opacity(0.2), lineWidth: 2))
                Text(store.quotaText).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                if store.isDemo { Circle().fill(.orange).frame(width: 4, height: 4) }
            }.frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 8)
        .frame(height: store.headerHeight)
        .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(store.expanded ? "点击收起" : "点击展开 · \(store.usageScope.title)今日 Token · 订阅窗口剩余额度")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(store.usageScope.title)今日 Token \(store.compactTokenText)，剩余额度 \(store.quotaText)")
        .accessibilityValue(store.expanded ? "已展开" : "已收起")
    }

    private var brandHeader: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(mint.opacity(0.14)).frame(width: 34, height: 34)
                Image(systemName: "circle.hexagongrid.fill").font(.system(size: 19)).foregroundStyle(mint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("TokenIsland").font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("每一份灵感，都有迹可循").font(.system(size: 10)).foregroundStyle(secondaryInk)
            }
            Spacer()
            if store.isDemo {
                Text("演示").font(.system(size: 9, weight: .medium)).foregroundStyle(.orange)
                    .padding(.horizontal, 7).padding(.vertical, 4).background(.orange.opacity(0.13), in: Capsule())
            }
            Button { store.setExpanded(false) } label: {
                Image(systemName: "chevron.up").foregroundStyle(secondaryInk)
                    .frame(width: 26, height: 26).contentShape(Rectangle())
            }.buttonStyle(.plain).help("收起灵动岛")
            if forExport { Image(systemName: "ellipsis").foregroundStyle(secondaryInk).frame(width: 24, height: 24) }
            else { Menu {
                Button("打开 ChatGPT", action: store.openChatGPT)
                Button("查看官方用量", action: store.openUsage)
                Button(store.isDemo ? "退出演示" : "预览演示数据") { store.setDemo(!store.isDemo) }
                Divider()
                Button("退出 TokenIsland") { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(secondaryInk).frame(width: 24, height: 24)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize() }
        }
    }

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 0) {
                ForEach(UsageScope.allCases, id: \.self) { scope in
                    Button { store.usageScope = scope } label: {
                        Text(scope.title).font(.system(size: 11, weight: .medium))
                            .foregroundStyle(store.usageScope == scope ? mint : secondaryInk)
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 5).fill(store.usageScope == scope ? mint.opacity(0.12) : .clear))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityValue(store.usageScope == scope ? "已选择" : "未选择")
                }
            }.padding(2).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
                .help("账号统计覆盖服务端已汇总活动；本机实时统计桌面任务记录")
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.usageScope == .account ? "今日 TOKEN · 账号" : "今日 TOKEN · 本机").font(.system(size: 10, weight: .medium)).tracking(1.3).foregroundStyle(secondaryInk)
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(TokenFormat.compact(store.todayTokens))
                            .font(.system(size: 34, weight: .medium, design: .rounded)).tracking(-1.5).monospacedDigit()
                        Text("tokens").font(.system(size: 10)).foregroundStyle(secondaryInk)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 7) {
                    HStack(spacing: 5) {
                        Circle().fill(mint).frame(width: 5, height: 5)
                        Text("ChatGPT · \(store.snapshot?.plan.capitalized ?? "")")
                    }.font(.system(size: 10, weight: .medium)).foregroundStyle(mint)
                    Text(Date(), format: .dateTime.month(.abbreviated).day())
                        .font(.system(size: 10)).foregroundStyle(secondaryInk)
                }.padding(.top, 4)
            }
            if store.usageScope == .account, store.todayTokens == nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text("账号今日用量待同步").foregroundStyle(mint.opacity(0.8))
                    if let latest = store.snapshot?.latestAccountDay {
                        Text("最近已同步 \(latest.startDate) · \(TokenFormat.compact(latest.tokens)) tokens")
                            .foregroundStyle(secondaryInk)
                    }
                }.font(.system(size: 10))
            }
            quotaCard
            hourlyChart
            Divider().overlay(.white.opacity(0.04))
            calendarView
        }
    }

    private var quotaCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("订阅剩余额度").foregroundStyle(.white.opacity(0.75))
                Spacer()
                if let buckets = store.snapshot?.limits?.buckets, buckets.count > 1 {
                    Menu {
                        ForEach(buckets, id: \.id) { item in
                            Button(item.bucket.limitName ?? item.id) { store.selectedBucketID = item.id }
                        }
                    } label: {
                        Text(store.selectedBucket?.limitName ?? store.selectedBucket?.limitId ?? "额度桶")
                            .font(.system(size: 9)).lineLimit(1).frame(maxWidth: 100)
                    }.menuStyle(.borderlessButton).fixedSize()
                }
                Text(store.quotaText).font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(quotaColor)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.08))
                    Capsule().fill(quotaColor).frame(width: geometry.size.width * CGFloat((store.quota?.remaining ?? 0) / 100))
                }
            }.frame(height: 4)
            HStack {
                Text(store.quota?.label ?? "额度未提供")
                Spacer()
                if let secondary = store.selectedBucket?.secondary, store.selectedBucket?.primary != nil {
                    Text("\(secondary.label)剩余 \(Int(secondary.remaining))%")
                } else if let reset = store.quota?.resetsAt {
                    Text("重置于 \(Date(timeIntervalSince1970: reset).formatted(.dateTime.month().day().hour().minute()))")
                }
            }.font(.system(size: 9)).foregroundStyle(secondaryInk)
        }.padding(13).background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.045)))
    }
    private var quotaColor: Color { (store.quota?.remaining ?? 100) <= 20 ? .orange : mint }

    private var hourlyChart: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(store.usageScope == .account ? "账号增量观测" : "今日消耗").font(.system(size: 12, weight: .medium))
                Spacer()
                Text("按小时").font(.system(size: 9)).foregroundStyle(secondaryInk)
            }
            Chart {
                ForEach(store.hours) { point in
                    let hour = Calendar.current.component(.hour, from: point.hour)
                    AreaMark(x: .value("小时", hour), y: .value("Tokens", point.tokens))
                        .foregroundStyle(LinearGradient(colors: [mint.opacity(0.25), mint.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.linear)
                    LineMark(x: .value("小时", hour), y: .value("Tokens", point.tokens))
                        .foregroundStyle(mint).lineStyle(StrokeStyle(lineWidth: 1.8)).interpolationMethod(.linear)
                    PointMark(x: .value("小时", hour), y: .value("Tokens", point.tokens))
                        .foregroundStyle(mint).symbolSize(10)
                }
            }
            .chartXScale(domain: 0...23)
            .chartYScale(domain: 0...max(1000, store.hours.map(\.tokens).max() ?? 1000))
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                    AxisValueLabel { if let h = value.as(Int.self) { Text(String(format: "%02d", h)).font(.system(size: 8)).foregroundStyle(secondaryInk) } }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4])).foregroundStyle(.white.opacity(0.09))
                    AxisValueLabel { if let v = value.as(Int.self) { Text(TokenFormat.compact(v)).font(.system(size: 8)).foregroundStyle(secondaryInk) } }
                }
            }
            .frame(height: 88)
            .accessibilityLabel("今日按小时观测的 Token 消耗")
            .overlay {
                if store.hours.isEmpty {
                    VStack(spacing: 7) {
                        Text(store.usageScope == .account ? "账号接口未提供小时明细" : "本机暂无小时记录")
                            .font(.system(size: 11)).foregroundStyle(secondaryInk)
                        if store.usageScope == .account {
                            Button("查看本机小时曲线") { store.usageScope = .local }
                                .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(mint)
                        }
                    }.padding(8).background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            Text(store.samplingNote).font(.system(size: 8)).foregroundStyle(secondaryInk)
        }
    }

    private var calendarView: some View {
        let calendar = Calendar.current
        let dates = DayKey.recentDates(now: Date())
        let offset = (calendar.component(.weekday, from: dates[0]) + 5) % 7
        let count = ((offset + dates.count + 6) / 7) * 7
        let maximum = max(1, dates.compactMap { store.snapshot?.tokens(on: $0) }.max() ?? 1)
        let selectedTokens = store.snapshot?.tokens(on: store.selectedDate)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("用量日历 · 账号").font(.system(size: 12, weight: .medium))
                Spacer()
                Text("最近 30 天").font(.system(size: 9)).foregroundStyle(secondaryInk)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 5) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { day in
                    Text(day).font(.system(size: 8)).foregroundStyle(secondaryInk).frame(height: 11)
                }
                ForEach(0..<count, id: \.self) { index in
                    if index >= offset && index < offset + dates.count {
                        let date = dates[index - offset]
                        let tokens = store.snapshot?.tokens(on: date)
                        let selected = calendar.isDate(date, inSameDayAs: store.selectedDate)
                        Button { store.selectedDate = date } label: {
                            Text("\(calendar.component(.day, from: date))")
                                .font(.system(size: 9, weight: selected ? .semibold : .regular, design: .rounded))
                                .foregroundStyle(tokens == nil ? secondaryInk : .white.opacity(0.85))
                                .frame(maxWidth: .infinity).frame(height: 23)
                                .background(RoundedRectangle(cornerRadius: 4).fill(heatColor(tokens, maximum: maximum)))
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(selected ? mint : .clear, lineWidth: 1))
                        }.buttonStyle(.plain)
                            .help("\(DayKey.string(date)) · \(tokens.map { "\($0.formatted()) tokens" } ?? "无数据")")
                            .accessibilityLabel("\(DayKey.string(date))，\(tokens.map { "\($0) tokens" } ?? "无数据")")
                    } else { Color.clear.frame(height: 23) }
                }
            }
            HStack {
                Text("\(store.selectedDate.formatted(.dateTime.month().day())) · \(selectedTokens.map { "\($0.formatted()) tokens" } ?? "无数据")")
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("少")
                ForEach(0..<5) { i in RoundedRectangle(cornerRadius: 2).fill(i == 0 ? .white.opacity(0.055) : mint.opacity(Double(i) * 0.2)).frame(width: 7, height: 7) }
                Text("多")
            }.font(.system(size: 8)).foregroundStyle(secondaryInk)
        }
    }
    private func heatColor(_ tokens: Int?, maximum: Int) -> Color {
        guard let tokens else { return .white.opacity(0.025) }
        if tokens == 0 { return .white.opacity(0.07) }
        return mint.opacity(0.14 + 0.68 * sqrt(Double(tokens) / Double(maximum)))
    }

    private var connectionState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: store.isRefreshing ? "antenna.radiowaves.left.and.right" : "person.crop.circle")
                .font(.system(size: 39, weight: .ultraLight)).foregroundStyle(mint)
            Text(store.isRefreshing ? "正在连接 ChatGPT" : store.signedOut ? "连接你的 ChatGPT" : "暂时无法连接")
                .font(.system(size: 19, weight: .medium, design: .rounded))
            Text(store.error ?? "登录后，在这里查看 Token 用量\n和订阅剩余额度。")
                .font(.system(size: 11)).foregroundStyle(secondaryInk).multilineTextAlignment(.center).lineSpacing(5)
            if store.signedOut {
                Button(action: store.login) {
                    HStack(spacing: 9) {
                        Text(store.isLoggingIn ? "等待浏览器登录…" : "登录 ChatGPT")
                        Image(systemName: "arrow.up.right")
                    }.font(.system(size: 12, weight: .medium)).foregroundStyle(.black)
                        .padding(.horizontal, 24).padding(.vertical, 11).background(mint, in: Capsule())
                }.buttonStyle(.plain).disabled(store.isLoggingIn)
                Button("打开 ChatGPT 应用", action: store.openChatGPT).buttonStyle(.plain).foregroundStyle(secondaryInk)
            } else if !store.isRefreshing {
                Button("重新连接") { Task { await store.refresh() } }.buttonStyle(.bordered)
                Button("打开 ChatGPT", action: store.openChatGPT).buttonStyle(.plain).foregroundStyle(secondaryInk)
            }
            Spacer()
            Text("仅连接 ChatGPT 提供的账号用量服务").font(.system(size: 9)).foregroundStyle(secondaryInk)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 7) {
            if store.snapshot != nil, let message = store.error ?? store.snapshot?.warning {
                Text(message).font(.system(size: 9)).foregroundStyle(.orange).lineLimit(2)
            }
            HStack(spacing: 5) {
                Circle().fill(store.error == nil ? mint : .orange).frame(width: 4, height: 4)
                Text(store.isDemo ? "演示数据" : store.isRefreshing ? "同步中…" : store.snapshot == nil ? "等待连接" : "已同步 \(store.snapshot!.updatedAt.formatted(.dateTime.hour().minute()))")
                    .font(.system(size: 9)).foregroundStyle(secondaryInk)
                Spacer()
                Button(action: store.openUsage) { Text("官方用量 ↗").font(.system(size: 9)).foregroundStyle(secondaryInk) }.buttonStyle(.plain)
                Button { Task { await store.refresh() } } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10)).foregroundStyle(secondaryInk).frame(width: 23, height: 23)
                }.buttonStyle(.plain).disabled(store.isRefreshing || store.isDemo).help("刷新用量")
            }
            if store.snapshot != nil {
                Text(store.sourceNote)
                    .font(.system(size: 8)).foregroundStyle(.white.opacity(0.26))
            }
        }
    }
}
