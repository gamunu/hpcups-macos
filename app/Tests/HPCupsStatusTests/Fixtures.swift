import Foundation

/// Reply bodies in the shapes the DeskJet 2300 sends over LEDM. Namespaces,
/// prefixes and element order follow captures from the real printer.
enum Fixture {
    static func data(_ s: String) -> Data { Data(s.utf8) }

    private static func cartridge(label: String, state: String = "newGenuineHP", measured: String = "ok",
                                  brand: String = "HP", refilled: Bool = false, percent: Int?,
                                  product: String = "682") -> String {
        let pct = percent.map { "<dd:ConsumablePercentageLevelRemaining>\($0)</dd:ConsumablePercentageLevelRemaining>" } ?? ""
        return """
        <ccdyn:ConsumableInfo>
            <dd:ConsumableContentType>markingAgent</dd:ConsumableContentType>
            <dd:ConsumableLabelCode>\(label)</dd:ConsumableLabelCode>
            <dd:ConsumableLifeState>
                <dd:ConsumableState>\(state)</dd:ConsumableState>
                <dd:MeasuredQuantityState>\(measured)</dd:MeasuredQuantityState>
                <dd:Brand>\(brand)</dd:Brand>
                <dd:IsRefilled>\(refilled)</dd:IsRefilled>
            </dd:ConsumableLifeState>
            \(pct)
            <dd:ConsumableSelectibilityNumber>\(product)</dd:ConsumableSelectibilityNumber>
            <dd:ConsumableTypeEnum>inkCartridge</dd:ConsumableTypeEnum>
        </ccdyn:ConsumableInfo>
        """
    }

    static func consumableConfig(_ cartridges: [String], alignment: String = "semiAutomatic") -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!--          THIS DATA SUBJECT TO DISCLAIMER(S) INCLUDED WITH THE PRODUCT OF ORIGIN.           -->
        <ccdyn:ConsumableConfigDyn xmlns:dd="http://www.hp.com/schemas/imaging/con/dictionaries/1.0/" xmlns:ccdyn="http://www.hp.com/schemas/imaging/con/ledm/consumableconfigdyn/2007/11/19">
            <dd:Version><dd:Revision>SVN-IPG-LEDM.290</dd:Revision></dd:Version>
            <ccdyn:ProductConsumableInfo>
                <dd:NumOfUserReplaceableConsumables>2</dd:NumOfUserReplaceableConsumables>
                <dd:AlignmentMode>\(alignment)</dd:AlignmentMode>
                <ccdyn:SupportedConsumables>
                    <ccdyn:SupportedConsumable>
                        <dd:ConsumableTypeEnum>inkCartridge</dd:ConsumableTypeEnum>
                        <dd:ConsumableLabelCode>CMY</dd:ConsumableLabelCode>
                    </ccdyn:SupportedConsumable>
                </ccdyn:SupportedConsumables>
            </ccdyn:ProductConsumableInfo>
            \(cartridges.joined(separator: "\n"))
        </ccdyn:ConsumableConfigDyn>
        """
    }

    static func ink(label: String, state: String = "newGenuineHP", measured: String = "ok", brand: String = "HP",
                    refilled: Bool = false, percent: Int?) -> String {
        cartridge(label: label, state: state, measured: measured, brand: brand, refilled: refilled, percent: percent)
    }

    /// CMY 90 percent, K 100 percent, both new genuine HP 682.
    static let consumablesTwoCartridges = consumableConfig([
        ink(label: "CMY", percent: 90),
        ink(label: "K", percent: 100),
    ])

    static func productStatus(_ categories: [String]) -> String {
        let statuses = categories.map {
            "<psdyn:Status><pscat:StatusCategory>\($0)</pscat:StatusCategory><locid:StringId>65561</locid:StringId></psdyn:Status>"
        }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!-- THIS DATA SUBJECT TO DISCLAIMER(S) INCLUDED WITH THE PRODUCT OF ORIGIN. -->
        <psdyn:ProductStatusDyn xmlns:dd="http://www.hp.com/schemas/imaging/con/dictionaries/1.0/" xmlns:pscat="http://www.hp.com/schemas/imaging/con/ledm/productstatuscategories/2007/10/31" xmlns:locid="http://www.hp.com/schemas/imaging/con/ledm/localizationids/2007/10/31" xmlns:psdyn="http://www.hp.com/schemas/imaging/con/ledm/productstatusdyn/2007/10/31">
            <dd:Version><dd:Revision>SVN-IPG-LEDM.216</dd:Revision></dd:Version>
            \(statuses)
            <psdyn:AlertTable>
                <dd:ModificationNumber>114</dd:ModificationNumber>
                <psdyn:Alert><dd:SequenceNumber>70</dd:SequenceNumber></psdyn:Alert>
            </psdyn:AlertTable>
        </psdyn:ProductStatusDyn>
        """
    }

    static func calibrationState(_ word: String) -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?> <!-- THIS DATA SUBJECT TO DISCLAIMER(S) INCLUDED WITH THE PRODUCT OF ORIGIN. --> <CalibrationState xmlns=\"http://www.hp.com/schemas/imaging/con/cnx/markingagentcalibration/2009/04/08\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\">\(word)</CalibrationState>"
    }

    /// Completed print jobs, one canceled calibration job with a nested CalibrationStateAccess,
    /// and an optional job that is still running.
    static func jobList(extraJob: (category: String, state: String)? = nil) -> String {
        func job(_ n: Int, _ category: String, _ state: String, nested: String = "") -> String {
            """
            <j:Job>
                <j:JobUrl>/Jobs/JobList/\(n)</j:JobUrl>
                <j:JobCategory>\(category)</j:JobCategory>
                <j:JobState>\(state)</j:JobState>
                <j:JobStateUpdate>108-\(n)</j:JobStateUpdate>
                <j:JobSource>userIO</j:JobSource>
                \(nested)
            </j:Job>
            """
        }
        var jobs = [
            job(1, "Print", "Completed"),
            job(2, "Print", "Completed"),
            job(3, "Calibration", "Canceled",
                nested: "<CalibrationStateAccess xmlns=\"http://www.hp.com/schemas/imaging/con/cnx/markingagentcalibration/2009/04/08\">    <CalibrationState>CalibrationRequired</CalibrationState> </CalibrationStateAccess>"),
            job(4, "Print", "Completed"),
        ]
        if let e = extraJob { jobs.append(job(5, e.category, e.state)) }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!-- THIS DATA SUBJECT TO DISCLAIMER(S) INCLUDED WITH THE PRODUCT OF ORIGIN. -->
        <j:JobList xmlns:j="http://www.hp.com/schemas/imaging/con/ledm/jobs/2009/04/30" xmlns:dd="http://www.hp.com/schemas/imaging/con/dictionaries/1.0/">
            \(jobs.joined(separator: "\n"))
        </j:JobList>
        """
    }

    static let internalPrintCap = """
    <?xml version="1.0" encoding="UTF-8"?>
    <ipcap:InternalPrintCap xmlns:ipcap="http://www.hp.com/schemas/imaging/con/ledm/internalprintcap/2008/03/21" xmlns:ipdyn="http://www.hp.com/schemas/imaging/con/ledm/internalprintdyn/2008/03/21">
        <ipcap:SupportedJobs>
            <ipcap:Job><ipdyn:JobType>cleaningPage</ipdyn:JobType></ipcap:Job>
            <ipcap:Job><ipdyn:JobType>cleaningPageLevel2</ipdyn:JobType></ipcap:Job>
            <ipcap:Job><ipdyn:JobType>diagnosticsPage</ipdyn:JobType></ipcap:Job>
            <ipcap:Job><ipdyn:JobType>paperFeedCleaningPage</ipdyn:JobType></ipcap:Job>
            <ipcap:Job><ipdyn:JobType>ribSmearCleaningPage</ipdyn:JobType></ipcap:Job>
        </ipcap:SupportedJobs>
    </ipcap:InternalPrintCap>
    """

    // MARK: HTTP framing

    static func httpOK(_ body: String) -> Data {
        let n = Data(body.utf8).count
        return Data("HTTP/1.1 200 OK\r\nContent-Type: text/xml\r\nContent-Length: \(n)\r\n\r\n\(body)".utf8)
    }

    static func httpChunked(_ body: String, chunkSize: Int) -> Data {
        var out = Data("HTTP/1.1 200 OK\r\nContent-Type: text/xml\r\nTransfer-Encoding: chunked\r\n\r\n".utf8)
        let bytes = Array(body.utf8)
        var i = 0
        while i < bytes.count {
            let part = bytes[i..<min(i + chunkSize, bytes.count)]
            out.append(Data(String(part.count, radix: 16).utf8))
            out.append(Data("\r\n".utf8))
            out.append(Data(part))
            out.append(Data("\r\n".utf8))
            i += chunkSize
        }
        out.append(Data("0\r\n\r\n".utf8))
        return out
    }
}
