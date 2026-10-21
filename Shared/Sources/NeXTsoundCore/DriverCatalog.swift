import Foundation

public extension DriverRecord {
    /// The only driver currently in use. Values come from the full parameter table in
    /// `DS-TEBM28C10-4/A revision 1.7` (the already-linked datasheet; an earlier reading of it
    /// missed this table and left most fields nil). Mounting/fit fields stay nil where the
    /// datasheet's own outline drawing does not give them cleanly: the drawing splits overall
    /// depth into front/rear segments without itemizing which is which, and does not label a
    /// mounting hole diameter, so neither is guessed.
    static func tectonicTEBM28C10_4() -> DriverRecord {
        let id = UUID(uuid: (0xD4, 0x71, 0x0E, 0x1C, 0x7E, 0x58, 0x4A, 0x8A, 0x9B, 0x6E, 0x0C, 0x28, 0xC1, 0x04, 0x7A, 0x2D))
        var driver = DriverRecord(id: id, name: "Tectonic Elements TEBM28C10-4")
        driver.manufacturer = "Tectonic Elements"
        driver.model = "TEBM28C10-4"
        driver.origin = .datasheet
        driver.sourceURLs = [
            URL(string: "https://doc.soundimports.nl/pdf/brands/Tectonic%20Elements/TEBM28C10-4.A%20BMR/tebm28c10-4a-spec-sheet.pdf")!,
        ]
        driver.nominalImpedanceOhms = 4
        driver.reOhms = 4.40
        driver.leMillihenries = 0.09
        driver.blTeslaMeters = 2.87
        driver.fsHz = 130
        driver.qts = 0.39
        driver.qes = 0.45
        driver.qms = 2.74
        driver.vasLiters = 0.15
        driver.sdSquareCentimeters = 8.55
        driver.mmsGrams = 1.0
        driver.xmaxMillimeters = 4.0
        driver.frameDiameterMillimeters = 46
        driver.mountingPitchCircleDiameterMillimeters = 48.0
        driver.mountingHoleCount = 4
        driver.ratedPowerWatts = 10
        driver.notes = """
        Datasheet identifies the model as TEBM28C10-4/A; the CAD reference labels it \
        TEBM28C10-4B. The correspondence between this physical unit and either identity is \
        not verified. Fs is typical with plus-or-minus 20% tolerance, not a measured value. \
        The 10 W rating is continuous weighted pink noise per IEC268-5 with a second-order \
        high-pass; no cutoff frequency is specified. The datasheet states maximum coil \
        excursion as 8.0 mm peak-to-peak; xmaxMillimeters holds half of that (4.0 mm one-way) \
        to match this field's one-way convention. Mounting pitch circle diameter (48.0 mm) and \
        hole count (4, read directly from the outline drawing) agree with the independently \
        measured enclosure CAD record's pilot pattern.
        """
        return driver
    }

    /// A candidate full-range driver within the enclosure's size and depth envelope, read from
    /// Tectonic Audio Labs' own `TEBM28C10-4B Datasheet 4/7/2026 E`. Deliberately a different
    /// tuning than `tectonicTEBM28C10_4()`'s TEBM28C10-4/A, not a substitute for it.
    static func tectonicTEBM28C10_4B() -> DriverRecord {
        let id = UUID(uuid: (0x7A, 0x2C, 0x5E, 0x91, 0x3F, 0x04, 0x4B, 0x6D, 0x8A, 0x1E, 0x2F, 0x53, 0x9C, 0x60, 0x1D, 0x44))
        var driver = DriverRecord(id: id, name: "Tectonic Audio Labs TEBM28C10-4B")
        driver.manufacturer = "Tectonic Audio Labs"
        driver.model = "TEBM28C10-4B"
        driver.origin = .datasheet
        driver.sourceURLs = [
            URL(
                string: "https://cdn.prod.website-files.com/673cf5977476dddd8360dc22/6a0b836f99600e7de8684726_TEBM28C10-4B%20Datasheet.pdf"
            )!,
        ]
        driver.nominalImpedanceOhms = 4
        driver.reOhms = 3.65
        driver.leMillihenries = 0.06
        driver.blTeslaMeters = 3.04
        driver.fsHz = 167
        driver.qts = 0.48
        driver.sdSquareCentimeters = 8.55
        driver.mmsGrams = 1.36
        driver.xmaxMillimeters = 1.4
        driver.frameDiameterMillimeters = 46
        driver.mountingPitchCircleDiameterMillimeters = 48.0
        driver.mountingHoleDiameterMillimeters = 3.3
        driver.mountingHoleCount = 4
        driver.ratedPowerWatts = 10
        driver.notes = """
        Datasheet revision E, 4/7/2026. Qes/Qms are not given, only the combined Qts. Vas is \
        not given; Cms (0.67 mm/N) and Mms are, but Vas is not computed from them here since \
        the datasheet does not state it directly. Overall depth is 25.8 mm; the datasheet's \
        drawing does not itemize a front/rear split, so frontProtrusionMillimeters and \
        rearDepthMillimeters stay nil rather than guessed. Max linear excursion is stated as \
        2.8 mm peak-to-peak (Klippel LSI); xmaxMillimeters holds half of that (1.4 mm \
        one-way). Mounting pitch circle (48.0 mm from a 33.9 mm square hole spacing) and hole \
        diameter (3.3 mm) match the independently measured enclosure CAD record.
        """
        return driver
    }

    /// A candidate full-range driver, read from Tectonic Audio Labs' own
    /// `TEBM28C10-4BE Datasheet 1/20/2025 D`. Tectonic's own product family page describes this
    /// as "reduced cost and sensitivity for alternative alignments" relative to -4B, i.e. a
    /// deliberately different tuning, not an equivalent part.
    static func tectonicTEBM28C10_4BE() -> DriverRecord {
        let id = UUID(uuid: (0x3B, 0x8F, 0x14, 0x6A, 0xC2, 0x05, 0x4E, 0x97, 0xB3, 0x2D, 0x19, 0x7C, 0xE8, 0x40, 0x6F, 0x11))
        var driver = DriverRecord(id: id, name: "Tectonic Audio Labs TEBM28C10-4BE")
        driver.manufacturer = "Tectonic Audio Labs"
        driver.model = "TEBM28C10-4BE"
        driver.origin = .datasheet
        driver.sourceURLs = [
            URL(
                string: "https://cdn.prod.website-files.com/673cf5977476dddd8360dc22/682e6b35682d8403c98aeb43_TEBM28C10-4BE%20Datasheet%20Rev.%20D.pdf"
            )!,
        ]
        driver.nominalImpedanceOhms = 4
        driver.reOhms = 3.7
        driver.leMillihenries = 0.10
        driver.blTeslaMeters = 2.12
        driver.fsHz = 161
        driver.qts = 0.82
        driver.sdSquareCentimeters = 8.55
        driver.mmsGrams = 1.11
        driver.xmaxMillimeters = 1.4
        driver.frameDiameterMillimeters = 46
        driver.mountingPitchCircleDiameterMillimeters = 48.0
        driver.mountingHoleDiameterMillimeters = 3.3
        driver.mountingHoleCount = 4
        driver.ratedPowerWatts = 10
        driver.notes = """
        Datasheet revision D, 1/20/2025. Qes/Qms are not given, only the combined Qts. Vas is \
        not given; Cms (0.88 mm/N) and Mms are, but Vas is not computed from them here since \
        the datasheet does not state it directly. Overall depth is 24 mm; front/rear split \
        stays nil for the same reason as TEBM28C10-4B. Max linear excursion is stated as \
        2.8 mm peak-to-peak (Klippel LSI); xmaxMillimeters holds half of that (1.4 mm \
        one-way). Mounting pitch circle and hole diameter match TEBM28C10-4B's drawing.
        """
        return driver
    }

    /// A candidate full-range driver within the 1.5"-2" / <=28 mm depth envelope, read from the
    /// official Dayton Audio / Parts Express specification sheet for the CE41N-4.
    static func daytonAudioCE41N4() -> DriverRecord {
        let id = UUID(uuid: (0x5D, 0x27, 0x9A, 0x33, 0xE4, 0x06, 0x41, 0xB8, 0x9F, 0x1C, 0x48, 0xA5, 0xD2, 0x70, 0x3E, 0x62))
        var driver = DriverRecord(id: id, name: "Dayton Audio CE41N-4")
        driver.manufacturer = "Dayton Audio"
        driver.model = "CE41N-4"
        driver.origin = .datasheet
        driver.sourceURLs = [
            URL(string: "https://www.parts-express.com/pedocs/specs/285-157--dayton-audio-ce41n-4-specification-sheet.pdf")!,
        ]
        driver.nominalImpedanceOhms = 4
        driver.reOhms = 3.6
        driver.leMillihenries = 0.06
        driver.blTeslaMeters = 2.30
        driver.fsHz = 170
        driver.qts = 0.53
        driver.qes = 0.58
        driver.qms = 5.60
        driver.vasLiters = 0.078
        driver.sdSquareCentimeters = 7.1
        driver.mmsGrams = 0.80
        driver.xmaxMillimeters = 0.7
        driver.frameDiameterMillimeters = 41.0
        driver.mountingPitchCircleDiameterMillimeters = 46.0
        driver.mountingHoleDiameterMillimeters = 3.0
        driver.mountingHoleCount = 4
        driver.ratedPowerWatts = 5
        driver.notes = """
        1.5" dual-neodymium full-range, 5 W RMS (AES 426B). Overall depth 27.3 mm, within the \
        enclosure's 28 mm envelope. Xmax (0.7 mm) is given directly as a one-way value in this \
        datasheet, unlike the Tectonic family's peak-to-peak convention, so no conversion is \
        applied here. The mounting holes are called out as "4-M3" (M3 thread), not a measured \
        clearance diameter; mountingHoleDiameterMillimeters holds the M3 nominal size (3.0 mm) \
        as the closest available reading, not a measured clearance hole.
        """
        return driver
    }

    /// A candidate full-range driver read from Visaton's own single-product data sheet for the
    /// FR 58 - 4 Ohm. At 58.5 mm (2.3") it is slightly larger than the requested 1.5"-2" range.
    /// Visaton's own sheet gives only these basic values and states that its full Thiele/Small
    /// table is in its printed catalog (pages 385-386), which this source does not include;
    /// Qts/Qes/Qms/Vas/Sd/Mms/Bl/Re/Le stay nil rather than taken from third-party aggregations
    /// that cannot be checked against Visaton's own source.
    static func visatonFR58_4() -> DriverRecord {
        let id = UUID(uuid: (0x91, 0x4C, 0x6E, 0x58, 0x2A, 0x07, 0x4D, 0xA1, 0x8E, 0x35, 0x7B, 0x1F, 0x60, 0xC9, 0x42, 0x29))
        var driver = DriverRecord(id: id, name: "Visaton FR 58 - 4 Ohm")
        driver.manufacturer = "Visaton"
        driver.model = "FR 58 (Art. No. 2204)"
        driver.origin = .datasheet
        driver.sourceURLs = [
            URL(string: "https://www.visaton.de/sites/default/files/dd_product/FR%2058_2204_2205.pdf")!,
        ]
        driver.nominalImpedanceOhms = 4
        driver.fsHz = 190
        driver.xmaxMillimeters = 2.5
        driver.frameDiameterMillimeters = 58.5
        driver.mountingPitchCircleDiameterMillimeters = 64.5
        driver.mountingHoleDiameterMillimeters = 5.5
        driver.mountingHoleCount = 4
        driver.ratedPowerWatts = 10
        driver.notes = """
        Square metal basket, 58.5 x 58.5 mm; frameDiameterMillimeters holds the side length, \
        not a true diameter. Depth is 28 mm, exactly the enclosure's stated envelope. \
        xmaxMillimeters holds the sheet's own "excursion limit xmech" (+/-2.5 mm), the only \
        excursion figure this sheet gives; it is a mechanical limit, not a linear-excursion \
        rating. Cutout diameter is 57 mm. 2.3" overall diameter is somewhat larger than the \
        requested 1.5"-2" range.
        """
        return driver
    }

    /// The 8 ohm counterpart to `visatonFR58_4()`, same physical part, read from Visaton's own
    /// single-product data sheet (05.09.2017) for Art. No. 2205. Unlike the 4 ohm sheet, this
    /// one does publish a full Thiele/Small table.
    static func visatonFR58_8() -> DriverRecord {
        let id = UUID(uuid: (0x57, 0x4F, 0x64, 0x7D, 0x66, 0xC8, 0x46, 0x03, 0x80, 0x94, 0x67, 0x70, 0xD7, 0x15, 0x23, 0x46))
        var driver = DriverRecord(id: id, name: "Visaton FR 58 - 8 Ohm")
        driver.manufacturer = "Visaton"
        driver.model = "FR 58 (Art. No. 2205)"
        driver.origin = .datasheet
        driver.sourceURLs = [
            URL(string: "https://www.visaton.de/sites/default/files/dd_product/fr58_8.pdf")!,
        ]
        driver.nominalImpedanceOhms = 8
        driver.reOhms = 7.3
        driver.leMillihenries = 0.15
        driver.blTeslaMeters = 2.27
        driver.fsHz = 190
        driver.qts = 0.98
        driver.qes = 1.64
        driver.qms = 2.41
        driver.vasLiters = 0.18
        driver.sdSquareCentimeters = 13.2
        driver.mmsGrams = 0.97
        driver.xmaxMillimeters = 5.5
        driver.frameDiameterMillimeters = 58.5
        driver.mountingPitchCircleDiameterMillimeters = 64.5
        driver.mountingHoleDiameterMillimeters = 5.5
        driver.mountingHoleCount = 4
        driver.ratedPowerWatts = 10
        driver.notes = """
        Square metal basket, 58.5 x 58.5 mm; frameDiameterMillimeters holds the side length, \
        not a true diameter. Depth is 28 mm, matching the 4 ohm variant and the enclosure's \
        stated envelope. Unlike the 4 ohm sheet, this one publishes a full Thiele/Small table \
        directly, so qts/qes/qms/vasLiters/sdSquareCentimeters/mmsGrams/blTeslaMeters/reOhms/ \
        leMillihenries all come straight from it rather than staying nil. xmaxMillimeters \
        holds the sheet's own "Grenzauslenkung xmech" (5.5 mm one-way), not the separately \
        stated "maximum linear displacement" (+/-0.55 mm); it is a mechanical limit, not a \
        linear-excursion rating. Cutout diameter is 57 mm.
        """
        return driver
    }

    /// A candidate miniature full-range driver read from Visaton's own shared datasheet for
    /// the BF 37 family (05.10.2018, catalog year 2026), which covers both impedance variants
    /// on one sheet. Optimized for small vented enclosures/passive-radiator enclosures per
    /// Visaton's own description, not the sealed enclosure this product actually uses.
    static func visatonBF37_4() -> DriverRecord {
        let id = UUID(uuid: (0x5C, 0x6F, 0xA3, 0xB6, 0x34, 0xDB, 0x4C, 0x65, 0x93, 0xFA, 0x91, 0xD4, 0xE1, 0xDA, 0x87, 0xCD))
        var driver = DriverRecord(id: id, name: "Visaton BF 37 - 4 Ohm")
        driver.manufacturer = "Visaton"
        driver.model = "BF 37 (Art. No. 2260)"
        driver.origin = .datasheet
        driver.sourceURLs = [
            URL(string: "https://www.visaton.de/sites/default/files/dd_product/BF37-4-8-Ohm_datasheet_2.pdf")!,
        ]
        driver.nominalImpedanceOhms = 4
        driver.fsHz = 170
        driver.xmaxMillimeters = 3.4
        driver.frameDiameterMillimeters = 41
        driver.mountingPitchCircleDiameterMillimeters = 35.5
        driver.mountingHoleDiameterMillimeters = 2.5
        driver.mountingHoleCount = 4
        driver.ratedPowerWatts = 5
        driver.notes = """
        Datasheet dated 05.10.2018 (2026 catalog reprint), shared across both impedance \
        variants (Art. No. 2260 = 4 ohm, 2261 = 8 ohm). As with FR 58, Visaton's own sheet \
        gives only these basic values, not a full Thiele/Small table; \
        qts/qes/qms/vasLiters/sdSquareCentimeters/mmsGrams/blTeslaMeters/reOhms/\
        leMillihenries all stay nil rather than taken from third-party aggregations that \
        cannot be checked against Visaton's own source. xmaxMillimeters holds the sheet's \
        own "excursion limit xmech" (+/-3.4 mm), a mechanical limit, not a linear-excursion \
        rating. Overall depth is 23.8 mm; the drawing gives two further depth figures \
        (21.5 mm, 12 mm) without labeling which marks a front/rear split, so \
        frontProtrusionMillimeters and rearDepthMillimeters stay nil rather than guessed.
        """
        return driver
    }

    /// The 8 ohm counterpart to `visatonBF37_4()`, same physical part and datasheet, Art. No. 2261.
    static func visatonBF37_8() -> DriverRecord {
        let id = UUID(uuid: (0xF3, 0x69, 0x43, 0x89, 0x64, 0x50, 0x4F, 0x1C, 0x85, 0xC6, 0xE0, 0x46, 0x70, 0xC4, 0xE4, 0x25))
        var driver = DriverRecord(id: id, name: "Visaton BF 37 - 8 Ohm")
        driver.manufacturer = "Visaton"
        driver.model = "BF 37 (Art. No. 2261)"
        driver.origin = .datasheet
        driver.sourceURLs = [
            URL(string: "https://www.visaton.de/sites/default/files/dd_product/BF37-4-8-Ohm_datasheet_2.pdf")!,
        ]
        driver.nominalImpedanceOhms = 8
        driver.fsHz = 170
        driver.xmaxMillimeters = 3.4
        driver.frameDiameterMillimeters = 41
        driver.mountingPitchCircleDiameterMillimeters = 35.5
        driver.mountingHoleDiameterMillimeters = 2.5
        driver.mountingHoleCount = 4
        driver.ratedPowerWatts = 5
        driver.notes = """
        Datasheet dated 05.10.2018 (2026 catalog reprint), shared across both impedance \
        variants (Art. No. 2260 = 4 ohm, 2261 = 8 ohm). As with FR 58, Visaton's own sheet \
        gives only these basic values, not a full Thiele/Small table; \
        qts/qes/qms/vasLiters/sdSquareCentimeters/mmsGrams/blTeslaMeters/reOhms/\
        leMillihenries all stay nil rather than taken from third-party aggregations that \
        cannot be checked against Visaton's own source. xmaxMillimeters holds the sheet's \
        own "excursion limit xmech" (+/-3.4 mm), a mechanical limit, not a linear-excursion \
        rating. Overall depth is 23.8 mm; the drawing gives two further depth figures \
        (21.5 mm, 12 mm) without labeling which marks a front/rear split, so \
        frontProtrusionMillimeters and rearDepthMillimeters stay nil rather than guessed.
        """
        return driver
    }
}
