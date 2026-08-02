import Foundation
import SwiftUI
import Testing
import UniformTypeIdentifiers
import Par

/// The tape's four promises from `plan_tape.md` §3, asserted against the real document code.
///
/// The app Par displaces is the one whose _"stored registers will 0 out for no reason whatsoever"_.
/// That is the failure these tests exist to prevent, and it is why the tape stores inputs only and
/// re-derives every number on open: a stored result can rot, an input cannot. So the shape of nearly
/// every test here is the same — record what a line reads, put the document through a real save and
/// a real reopen, and demand the identical string back. Not close; identical. A tolerance here would
/// be a licence for exactly the drift the incumbent shipped.
///
/// The three failure modes being ruled out, in the order a user would meet them:
///  1. a reopened line quietly reads differently from the one that was saved;
///  2. correcting one line disturbs another, so the tape stops being a record of independent solves;
///  3. a line the file format cannot read is dropped, guessed at, or overwritten on the next save.
///
/// ORACLES:
///  • IDENTITY — `configurationBridgeIsSound`, `reopenedLinesReSolveIdentically`,
///    `solverIsDeterministic`, `oneLineSolvesTheSameInALargeTape`, `labelsOrderingAndTimestampsSurviveDisk`:
///    a value is carried through a transformation (save/open, repetition, bulk) and must come back
///    unchanged. The transformation is the identity on what the user can see.
///  • INVARIANT — `editingLineTwoLeavesItsNeighboursAlone`, `largeTapeOpensWithoutSolvingEveryLine`,
///    `damagedLineSurvivesWithItsSummary`, `resavingADamagedLineDoesNotBakeTheDamageIn`,
///    `csvQuotesLabelsContainingCommasAndQuotes`, `plainTextHasOneEntryPerRow`: a property that must
///    hold over every document, asserted on a document constructed to stress it.
@Suite("Tape — save, reopen, correct, export")
struct TapeTests {

    // MARK: - Sample tape

    /// One row per non-damaged `SolveInputs` case, so a round trip exercises every branch of the
    /// enum's codability rather than the one case that happens to be in the UI's default state.
    /// Values are the ones the screens actually produce (see the view models), and each must solve to
    /// a number — an `.unavailable` line would satisfy the identity below without proving anything.
    static let sampleInputs: [SolveInputs] = [
        .tvm(TVMInputs(periods: 360, annualRatePct: 6.25, presentValue: 420_000,
                       payment: 0, futureValue: 0, solveFor: "payment")),
        .amortization(AmortInputs(principal: 420_000, annualRatePct: 6.25,
                                  periods: 360, periodsPerYear: 12)),
        .cashFlow(CashFlowInputs(groups: [.init(amount: -100_000, count: 1),
                                          .init(amount: 28_000, count: 5)],
                                 discountRatePct: 8)),
        .bond(BondInputs(couponPct: 4.25, price: 98.75, fullPeriods: 20,
                         daysToNextCoupon: 91, daysInPeriod: 181,
                         conventionRawValue: "regular")),
        .rate(RateInputs(mode: "apr")),
        .depreciation(DepInputs(cost: 100_000, salvage: 0, recoveryYears: 7, factor: 2,
                                methodRawValue: "macrsGDS", conventionRawValue: "halfYear")),
        .dayCount(DayCountInputs(start: 20_250_131, end: 20_260_228,
                                 conventionRawValue: "thirtyE360ISDA")),
        .percent(PercentInputs(mode: "margin", cost: 60, price: 100)),
        .statistics(StatInputs(xs: [1, 2, 3, 4, 5], ys: [12, 19, 29, 37, 45],
                               modelRawValue: "linear", forecastX: 6)),
        .realEstate(RealEstateInputs(grossPotentialRent: 480_000, vacancyPct: 5, otherIncome: 12_000,
                                     operatingExpenses: 190_000, reserves: 9_600, value: 4_200_000,
                                     targetDSCR: 1.25, maxLTVPct: 70, annualRatePct: 6.5,
                                     amortizationYears: 30)),
    ]

    /// Labels deliberately mixed: mostly empty, occasionally long, one with the punctuation a client
    /// name really contains. Timestamps are whole seconds a minute apart — see
    /// `labelsOrderingAndTimestampsSurviveDisk` for why the second is the resolution on offer.
    static let sampleLabels = [
        "123 Oak St — 30yr", "", "Warehouse — Alvarez", "Treasury 2031", "",
        "Truck loan", "Mid-quarter check", "Settlement 31 Jan → 28 Feb", "", "Rent roll 2026",
    ]

    static let epoch = Date(timeIntervalSince1970: 1_785_000_000)

    static let sampleRows: [TapeRow] = sampleInputs.indices.map { index in
        TapeRow(label: sampleLabels[index], inputs: sampleInputs[index],
                createdAt: epoch.addingTimeInterval(Double(index) * 60))
    }

    static func sampleDocument(title: String = "Refi comparison — Alvarez") -> TapeDocument {
        var document = TapeDocument(title: title)
        // Through `append`, because that is the only way a line ever enters a tape in the app.
        for row in sampleRows { document.append(row) }
        return document
    }

    // MARK: - Claim 0: the bridge these tests stand on

    /// Not one of the four claims — the thing that makes the four testable. `Disk` reaches the
    /// document's real read and write entry points by building SwiftUI's two configuration structs,
    /// which have no public initialiser. If that construction is ever wrong, every other test in this
    /// file would be asserting against garbage, so it is checked first and explicitly.
    @Test("the read and write configurations reach the document intact")
    func configurationBridgeIsSound() throws {
        let bytes = Data(#"{"not":"a tape"}"#.utf8)
        let file = FileWrapper(regularFileWithContents: bytes)
        let read = try Disk.readConfiguration(file)

        #expect(read.file === file, "the document must be handed the very wrapper it is meant to read")
        #expect(read.file.regularFileContents == bytes, "the bytes must arrive unaltered")
        #expect(read.contentType == .parTape, "a tape is read as a tape, not as generic JSON")

        let write = try Disk.writeConfiguration()
        #expect(write.existingFile == nil, "a fresh save has no existing file behind it")
        #expect(write.contentType == .parTape)
    }

    // MARK: - Claim 1: append → close → reopen → every line re-solves identically

    @Test("every line re-solves to the stored result after a close and a reopen")
    func reopenedLinesReSolveIdentically() throws {
        let document = Self.sampleDocument()
        #expect(document.rows.count == 10, "the sample must cover every non-damaged input case")

        let before = document.rows.map { TapeSolver.result(for: $0.inputs) }
        for (index, result) in before.enumerated() {
            if case .unavailable(_, let reason) = result {
                let tool = document.rows[index].inputs.toolName
                Issue.record(Comment(rawValue:
                    "sample line \(index + 1) (\(tool)) does not solve — \(reason); "
                    + "an unsolvable sample would make the identity below vacuous"))
            }
        }

        let reopened = try Disk.roundTripViaDisk(document)

        #expect(reopened.title == document.title, "the tape's name is part of the record")
        #expect(reopened.rows.count == document.rows.count,
                "reopening must not lose a line — losing a line is the bug that killed the incumbent")

        for (index, row) in reopened.rows.enumerated() {
            let after = TapeSolver.result(for: row.inputs)
            let line = "line \(index + 1) (\(row.inputs.toolName))"

            #expect(row.inputs == document.rows[index].inputs,
                    Comment(rawValue: "\(line): the stored inputs came back changed"))
            #expect(after.name == before[index].name,
                    Comment(rawValue: "\(line): result is now called \(after.name), "
                            + "was \(before[index].name)"))
            // `==` on the formatted string, not a tolerance: the number the user reads must be the
            // same character sequence it was when they saved.
            #expect(after.formatted == before[index].formatted,
                    Comment(rawValue: "\(line): reads \(after.formatted) after reopening, "
                            + "read \(before[index].formatted) before"))
            #expect(after.spoken == before[index].spoken,
                    Comment(rawValue: "\(line): VoiceOver would now say \(after.spoken)"))
        }

        // The file must not carry a computed number at all. A stored result is what goes stale; the
        // format's defence against that is having nowhere to put one.
        let keys = try Disk.rowKeys(in: try Disk.save(document))
        #expect(keys == ["createdAt", "id", "inputs", "label", "rawSummary", "rawToolName"],
                Comment(rawValue: "a saved row carries \(keys.joined(separator: ", ")) — "
                        + "anything beyond inputs and description is a number that can rot"))
    }

    @Test("the solver returns the identical result every time it is asked",
          arguments: sampleInputs.indices)
    func solverIsDeterministic(index: Int) {
        let inputs = Self.sampleInputs[index]
        let first = TapeSolver.result(for: inputs)
        let second = TapeSolver.result(for: inputs)

        #expect(first == second,
                Comment(rawValue: "\(inputs.toolName) solved twice gave \(first.formatted) "
                        + "then \(second.formatted); a tape cannot re-derive what is not a function"))
    }

    // MARK: - Claim 2: edit line 2, and only line 2 moves

    @Test("correcting line 2 changes line 2 and leaves lines 1 and 3 alone")
    func editingLineTwoLeavesItsNeighboursAlone() throws {
        // Three refinance scenarios on one property — the case in plan_tape.md §3, and the one where
        // a running-total calculator would be actively wrong.
        func scenario(rate: Double) -> SolveInputs {
            .tvm(TVMInputs(periods: 360, annualRatePct: rate, presentValue: 420_000,
                           payment: 0, futureValue: 0, solveFor: "payment"))
        }
        var document = TapeDocument(title: "Refi comparison — Alvarez")
        for (index, rate) in [6.25, 5.75, 5.25].enumerated() {
            document.append(TapeRow(label: "scenario \(index + 1)", inputs: scenario(rate: rate),
                                    createdAt: Self.epoch.addingTimeInterval(Double(index))))
        }
        let before = document.rows.map { TapeSolver.result(for: $0.inputs) }
        let identities = document.rows.map(\.id)

        // The correction itself: the rate on line 2 was mistyped.
        document.rows[1].inputs = scenario(rate: 5.95)
        let after = document.rows.map { TapeSolver.result(for: $0.inputs) }

        #expect(after[1] != before[1],
                Comment(rawValue: "line 2 still reads \(after[1].formatted) after its rate changed"))
        #expect(after[0] == before[0],
                Comment(rawValue: "line 1 moved from \(before[0].formatted) to \(after[0].formatted) "
                        + "because line 2 was edited"))
        #expect(after[2] == before[2],
                Comment(rawValue: "line 3 moved from \(before[2].formatted) to \(after[2].formatted) "
                        + "because line 2 was edited"))
        // Independence is about the stored inputs too, not only about what they happen to solve to.
        #expect(document.rows[0].inputs == scenario(rate: 6.25))
        #expect(document.rows[2].inputs == scenario(rate: 5.25))
        #expect(document.rows.map(\.id) == identities,
                "an edit corrects a line in place; it does not replace it with a new one")

        // And the correction is what gets saved: reopening reads the corrected line back.
        let reopened = try Disk.roundTripViaDisk(document)
        for (index, row) in reopened.rows.enumerated() {
            let result = TapeSolver.result(for: row.inputs)
            #expect(result == after[index],
                    Comment(rawValue: "line \(index + 1) reopened as \(result.formatted), "
                            + "expected \(after[index].formatted)"))
        }
    }

    // MARK: - Claim 3: a 1,000-entry tape opens without recomputing everything

    /// Deliberately a solve with real work in it: `CashFlow.irr` samples the NPV curve 2,000 times.
    /// That is what makes the comparison below meaningful — if opening a tape solved its lines, it
    /// could not possibly finish faster than solving them.
    static func dealInputs(_ index: Int) -> SolveInputs {
        .cashFlow(CashFlowInputs(
            groups: [.init(amount: -(250_000 + Double(index)), count: 1),
                     .init(amount: 22_000 + Double(index % 7), count: 12)],
            discountRatePct: 8
        ))
    }

    static func largeTape() -> TapeDocument {
        var document = TapeDocument(title: "Ten years of deals")
        for index in 0..<1_000 {
            document.append(TapeRow(label: index % 3 == 0 ? "deal \(index)" : "",
                                    inputs: dealInputs(index),
                                    createdAt: epoch.addingTimeInterval(Double(index) * 3_600)))
        }
        return document
    }

    @Test("a 1,000-entry tape opens without solving every line")
    func largeTapeOpensWithoutSolvingEveryLine() throws {
        let saved = Self.largeTape()
        let bytes = try Disk.save(saved)
        let clock = ContinuousClock()

        var opened: TapeDocument?
        let opening = try clock.measure { opened = try Disk.open(bytes) }
        let document = try #require(opened, "a 1,000-entry tape must open at all")

        #expect(document.rows.count == 1_000,
                Comment(rawValue: "opened \(document.rows.count) of 1,000 lines"))
        #expect(document.rows.map(\.label) == saved.rows.map(\.label),
                "order and labels survive at volume, not only in a three-line tape")

        // Solving all thousand is the work opening is claimed not to do. Opening must therefore cost
        // a small fraction of it; the factor of five is slack for a cold cache, not a real tolerance
        // — the measured gap on this machine is nearer a hundredfold.
        let solvingEverything = clock.measure {
            for row in document.rows { _ = TapeSolver.result(for: row.inputs) }
        }
        let timings = "opening took \(opening), solving all 1,000 lines took \(solvingEverything)"
        #expect(opening * 5 < solvingEverything,
                Comment(rawValue: "opening looks like it solved the tape — \(timings)"))
        #expect(opening < .seconds(2),
                Comment(rawValue: "a 1,000-entry tape must open promptly — \(timings)"))
    }

    @Test("a line solves the same in a 1,000-line tape as it does on its own")
    func oneLineSolvesTheSameInALargeTape() throws {
        let document = try Disk.open(try Disk.save(Self.largeTape()))
        let row = document.rows[500]

        let inTape = TapeSolver.result(for: row.inputs)
        let alone = TapeSolver.result(for: Self.dealInputs(500))

        #expect(row.inputs == Self.dealInputs(500), "line 501 must be the line it was saved as")
        #expect(inTape == alone,
                Comment(rawValue: "line 501 reads \(inTape.formatted) inside a 1,000-line tape "
                        + "and \(alone.formatted) alone; a line's result cannot depend on its "
                        + "neighbours or on how many of them there are"))
    }

    // MARK: - Claim 4: labels, ordering, timestamps and a damaged line survive disk

    @Test("labels, ordering and timestamps survive a round trip through disk")
    func labelsOrderingAndTimestampsSurviveDisk() throws {
        let document = Self.sampleDocument(title: "Client file — Alvarez, 2026")
        let reopened = try Disk.roundTripViaDisk(document)

        #expect(reopened.title == document.title)
        #expect(reopened.rows.map(\.id) == document.rows.map(\.id),
                "the same lines, in the same order — identity and ordering are the record")
        #expect(reopened.rows.map(\.label) == document.rows.map(\.label),
                "the label is what turns a tape into a client record; it is not decoration")

        for (index, row) in reopened.rows.enumerated() {
            let original = document.rows[index]
            // Exact equality is available because the samples sit on whole seconds. The file's
            // ISO-8601 dates carry no fraction, so a line stamped `.now` loses its sub-second part —
            // harmless for display and ordering, and noted here so it is a known limit and not a
            // surprise.
            #expect(row.createdAt == original.createdAt,
                    Comment(rawValue: "line \(index + 1) came back stamped \(row.createdAt), "
                            + "was \(original.createdAt)"))
            #expect(row == original,
                    Comment(rawValue: "line \(index + 1) is not the line that was saved"))
        }
    }

    @Test("a line whose inputs will not decode survives, with its summary intact")
    func damagedLineSurvivesWithItsSummary() throws {
        let document = Self.sampleDocument()
        // Hand-crafted damage: valid JSON in the `inputs` slot, but no such tool. This is what a file
        // written by a future version, or a half-finished sync, would look like.
        let unknown: [String: Any] = ["unknownTool": ["x": 1]]
        let damagedBytes = try Disk.replacingInputs(ofRow: 1, in: try Disk.save(document), with: unknown)

        let opened = try Disk.open(damagedBytes)

        #expect(opened.rows.count == document.rows.count,
                "an unreadable line is kept and shown, never dropped")
        guard case .damaged(let damaged) = opened.rows[1].inputs else {
            Issue.record("line 2 should have opened as damaged, not as \(opened.rows[1].inputs.toolName)")
            return
        }
        #expect(damaged.rawSummary == TapeExport.summary(of: document.rows[1]),
                Comment(rawValue: "the summary is the only description of the line the user has "
                        + "left, and it reads \(damaged.rawSummary)"))
        #expect(damaged.toolName == document.rows[1].inputs.toolName,
                "the tool a damaged line came from is still known")
        #expect(!damaged.reason.isEmpty, "a damaged line has to say why")
        #expect(opened.rows[1].id == document.rows[1].id)
        #expect(opened.rows[1].label == document.rows[1].label, "the label outlives the inputs")
        #expect(opened.rows[1].createdAt == document.rows[1].createdAt)

        // It reads as unreadable, not as zero. This is precisely the incumbent's failure inverted.
        let result = TapeSolver.result(for: opened.rows[1].inputs)
        #expect(result.formatted == "—",
                Comment(rawValue: "a damaged line reads \(result.formatted); a zero here is the "
                        + "silent loss Par exists to replace"))
        #expect(TapeExport.summary(of: opened.rows[1]) == damaged.rawSummary,
                "the exported line falls back to the preserved summary")

        // One bad line, and one only — the rest of the tape is untouched and still solves.
        for index in opened.rows.indices where index != 1 {
            #expect(opened.rows[index].inputs == document.rows[index].inputs,
                    Comment(rawValue: "line \(index + 1) was collateral damage"))
            #expect(TapeSolver.result(for: opened.rows[index].inputs)
                    == TapeSolver.result(for: document.rows[index].inputs),
                    Comment(rawValue: "line \(index + 1) no longer re-solves the same"))
        }
    }

    @Test("re-saving a damaged line writes the original bytes back, not the damage")
    func resavingADamagedLineDoesNotBakeTheDamageIn() throws {
        let document = Self.sampleDocument()
        let unknown: [String: Any] = ["unknownTool": ["x": 1]]
        let damagedBytes = try Disk.replacingInputs(ofRow: 1, in: try Disk.save(document), with: unknown)
        let opened = try Disk.open(damagedBytes)

        // The user edits the label of another line and the document saves itself, as it does after
        // every change. The unreadable line must come through that save unharmed.
        var edited = opened
        edited.rows[0].label = "renamed"
        let resaved = try Disk.save(edited)

        let written = try Disk.inputsObject(ofRow: 1, in: resaved)
        #expect(NSDictionary(dictionary: written) == NSDictionary(dictionary: unknown),
                Comment(rawValue: "the quarantined bytes were rewritten as \(written) — the original "
                        + "inputs are now gone for good"))
        #expect(!String(decoding: resaved, as: UTF8.self).contains("damaged"),
                "writing the damage back would make the line decode 'successfully' as damaged forever")

        // A version that understands `unknownTool` would still find it there, so opening the resaved
        // file with this version produces exactly the damaged line it produced the first time.
        let reopened = try Disk.open(resaved)
        guard case .damaged(let again) = reopened.rows[1].inputs,
              case .damaged(let first) = opened.rows[1].inputs else {
            Issue.record("line 2 stopped being damaged across a save, which means its bytes changed")
            return
        }
        #expect(again == first, "a damaged line decodes identically on every subsequent open")
        #expect(reopened.rows[1].createdAt == opened.rows[1].createdAt)
        #expect(reopened.rows.map(\.id) == opened.rows.map(\.id), "ordering holds across the resave")
    }

    // MARK: - Export

    @Test("CSV quotes a label containing a comma and a quote")
    func csvQuotesLabelsContainingCommasAndQuotes() {
        let label = #"Alvarez, "final" offer"#
        var document = TapeDocument(title: "Export")
        document.append(TapeRow(label: label, inputs: Self.sampleInputs[0], createdAt: Self.epoch))

        let csv = TapeExport.csv(document)
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines.count == 2, Comment(rawValue: "one header and one line, got \(lines.count)"))

        // Parsing it back is the only assertion that matters: a spreadsheet has to see seven fields
        // and the label whole, commas and all.
        let header = Self.csvFields(lines[0])
        let fields = Self.csvFields(lines[1])
        #expect(fields.count == header.count,
                Comment(rawValue: "the label's comma split the row into \(fields.count) fields, "
                        + "against \(header.count) columns in the header"))
        #expect(fields[2] == label,
                Comment(rawValue: "the label parsed back as \(fields[2])"))
        #expect(lines[1].contains(#""Alvarez, ""final"" offer""#),
                "an embedded quote is doubled and the field is wrapped, per RFC 4180")
        // The inputs column contains thousands separators, so it is escaped for the same reason.
        #expect(fields[3] == TapeExport.summary(of: document.rows[0]),
                "the inputs column survives its own commas")
    }

    @Test("plain text carries one entry per row")
    func plainTextHasOneEntryPerRow() {
        let document = Self.sampleDocument()
        let text = TapeExport.plainText(document)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        for index in document.rows.indices {
            let row = document.rows[index]
            let heading = "\(index + 1). \(row.inputs.toolName)"
            #expect(lines.contains { $0.hasPrefix(heading) },
                    Comment(rawValue: "no entry headed \(heading) in the exported text"))
        }
        let entries = lines.filter { line in
            document.rows.indices.contains { line.hasPrefix("\($0 + 1). ") }
        }
        #expect(entries.count == document.rows.count,
                Comment(rawValue: "\(entries.count) entries for \(document.rows.count) rows"))
        #expect(text.contains("123 Oak St — 30yr"), "labels are part of the printed record")
        #expect(text.contains("\(document.rows.count) lines"), "the export states its own length")
        #expect(text.hasPrefix(document.title), "the sheet is headed with the tape's name")
    }

    // MARK: - CSV reader, for the escaping test only

    /// A minimal RFC 4180 field splitter. It exists so the escaping test asserts what a spreadsheet
    /// would see rather than what the exporter believes it wrote.
    static func csvFields(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var characters = Array(line)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if inQuotes {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        current.append("\"")   // a doubled quote is one literal quote
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(character)
                }
            } else if character == "\"" {
                inQuotes = true
            } else if character == "," {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }
            index += 1
        }
        fields.append(current)
        return fields
    }
}

// MARK: - Reaching the document's real read and write paths

/// SwiftUI's `FileDocumentReadConfiguration` and `FileDocumentWriteConfiguration` have public stored
/// properties and no public initialiser — outside a `DocumentGroup` there is no supported way to make
/// one. Testing the document through a reimplemented encoder instead would test the reimplementation,
/// so each configuration is built by reinterpreting a struct with the same stored properties in the
/// same order, guarded by a size check and verified end to end by `configurationBridgeIsSound`.
private enum Disk {

    private struct ReadLayout { let contentType: UTType; let file: FileWrapper }
    private struct WriteLayout { let contentType: UTType; let existingFile: FileWrapper? }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    static func readConfiguration(_ file: FileWrapper) throws -> FileDocumentReadConfiguration {
        guard MemoryLayout<ReadLayout>.size == MemoryLayout<FileDocumentReadConfiguration>.size else {
            throw Failure("FileDocumentReadConfiguration no longer has the layout this test mirrors")
        }
        let layout = ReadLayout(contentType: .parTape, file: file)
        return withUnsafePointer(to: layout) {
            $0.withMemoryRebound(to: FileDocumentReadConfiguration.self, capacity: 1) { $0.pointee }
        }
    }

    static func writeConfiguration() throws -> FileDocumentWriteConfiguration {
        guard MemoryLayout<WriteLayout>.size == MemoryLayout<FileDocumentWriteConfiguration>.size else {
            throw Failure("FileDocumentWriteConfiguration no longer has the layout this test mirrors")
        }
        let layout = WriteLayout(contentType: .parTape, existingFile: nil)
        return withUnsafePointer(to: layout) {
            $0.withMemoryRebound(to: FileDocumentWriteConfiguration.self, capacity: 1) { $0.pointee }
        }
    }

    /// The bytes the app would write, produced by the app's own `fileWrapper(configuration:)`.
    static func save(_ document: TapeDocument) throws -> Data {
        let wrapper = try document.fileWrapper(configuration: writeConfiguration())
        guard let data = wrapper.regularFileContents else {
            throw Failure("the document wrote a wrapper with no file contents in it")
        }
        return data
    }

    /// The document the app would open, produced by the app's own `init(configuration:)`.
    static func open(_ data: Data) throws -> TapeDocument {
        try TapeDocument(configuration: readConfiguration(FileWrapper(regularFileWithContents: data)))
    }

    /// Save, close, reopen — with a real file in between, so the trip is the one a user takes.
    static func roundTripViaDisk(_ document: TapeDocument) throws -> TapeDocument {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).partape")
        try save(document).write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }
        let wrapper = try FileWrapper(url: url, options: .immediate)
        return try TapeDocument(configuration: readConfiguration(wrapper))
    }

    // MARK: Inspecting and damaging saved bytes

    private static func rows(in data: Data) throws -> [[String: Any]] {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = payload["rows"] as? [[String: Any]] else {
            throw Failure("a saved tape is no longer {version, title, rows: [...]}")
        }
        return rows
    }

    /// The keys a saved row carries, sorted — used to prove no computed number is stored.
    static func rowKeys(in data: Data) throws -> [String] {
        guard let first = try rows(in: data).first else { throw Failure("no rows in the saved tape") }
        return first.keys.sorted()
    }

    static func inputsObject(ofRow index: Int, in data: Data) throws -> [String: Any] {
        let rows = try rows(in: data)
        guard rows.indices.contains(index), let inputs = rows[index]["inputs"] as? [String: Any] else {
            throw Failure("row \(index) has no object in its inputs slot")
        }
        return inputs
    }

    /// Substitutes an `inputs` payload into a genuinely saved file. Everything else — the id, label,
    /// timestamp, tool name and summary the encoder wrote — is left exactly as the app wrote it.
    static func replacingInputs(ofRow index: Int, in data: Data,
                                with object: [String: Any]) throws -> Data {
        guard var payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure("a saved tape is no longer a JSON object")
        }
        var rows = try rows(in: data)
        guard rows.indices.contains(index) else { throw Failure("no row \(index) to damage") }
        rows[index]["inputs"] = object
        payload["rows"] = rows
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }
}
