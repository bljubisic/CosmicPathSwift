//
//  InfoContent.swift
//  CosmicPathSwift
//
//  "What am I looking at?" (issue #34): plain-language explanations of the
//  current scene, built as data from a snapshot of the simulation so it can be
//  unit-tested without UI. `InfoSheetView` renders it.
//
//  Every number shared with the metrics panel comes from the same formatters
//  (`MetricsText`, `RealUnitsFormatter`, `SimulationConfig` labels), so the
//  sheet never contradicts the screen.
//

import Foundation

// MARK: - Snapshot

/// Everything the explanations depend on, captured from the view model.
struct InfoSnapshot {
    var config: SimulationConfig
    var metrics = RelativisticMetrics()
    var systemMetrics = SystemMetrics()
    /// Legend text per body, as shown on screen (`SimulationViewModel.bodyLabels`).
    var bodyLabels: [String] = []
    /// Canvas points per simulation length unit.
    var coordinateScale: Double = 1
    var habitableZone: HabitableZone?
    var habitableStatus: HabitableStatus?
    var planetEquilibriumTemperature: Double?
    var isHabitableZoneOffScreen = false
    /// The Realistic "1 s = X" rate in effect.
    var activeRealTimeRate: RealTimeRate = .oneMonth
}

// MARK: - Content

/// Sections explaining the current scene, in display order.
struct InfoContent {
    let sections: [InfoSection]

    func section(_ id: InfoSectionID) -> InfoSection? {
        sections.first { $0.id == id }
    }
}

enum InfoSectionID: Equatable, Sendable {
    case scene, scale, bodies, blackHole, habitableZone, display, metrics
}

struct InfoSection: Identifiable {
    let id: InfoSectionID
    let title: String
    /// Plain-language explanation, one string per paragraph.
    var paragraphs: [String] = []
    /// Label/value rows with the current numbers.
    var facts: [InfoFact] = []
    /// Short definitions of things on screen.
    var terms: [InfoTerm] = []

    /// The value of the fact labelled `label`, if any.
    func fact(_ label: String) -> String? {
        facts.first { $0.label == label }?.value
    }
}

struct InfoFact: Equatable, Sendable {
    let label: String
    let value: String
}

struct InfoTerm: Equatable, Sendable {
    let term: String
    let definition: String
}

// MARK: - Building

extension InfoContent {

    /// The explanations for `snapshot`, with only the sections that apply.
    static func make(from snapshot: InfoSnapshot) -> InfoContent {
        let builder = Builder(snapshot: snapshot)
        let sections: [InfoSection?] = [
            builder.scene, builder.scale, builder.bodies, builder.blackHole,
            builder.habitableZone, builder.display, builder.metricsSection
        ]
        return InfoContent(sections: sections.compactMap { $0 })
    }

    private struct Builder {
        let snapshot: InfoSnapshot

        private var config: SimulationConfig { snapshot.config }
        private var metrics: RelativisticMetrics { snapshot.metrics }
        private var text: MetricsText { MetricsText(config: config) }
        private var isThreeBody: Bool { config.mode == .threeBody }
        private var isBlackHole: Bool { !isThreeBody && metrics.isBlackHole }

        // MARK: Scene

        var scene: InfoSection {
            var section = InfoSection(id: .scene, title: "The Scene", paragraphs: [sceneSummary])
            section.facts.append(InfoFact(label: "Scale", value: config.isRealistic ? "Realistic" : "Visual"))
            if config.isRealistic {
                section.facts.append(InfoFact(label: "Time", value: snapshot.activeRealTimeRate.label))
            } else {
                section.facts.append(InfoFact(label: "Speed", value: String(format: "%g×", config.advanced.time.timeSpeed)))
            }
            return section
        }

        private var sceneSummary: String {
            if isThreeBody {
                var summary = "Three bodies pulling on each other: the \(config.threeBodyPreset.displayName) setup. "
                    + "No body is fixed, and there is no exact solution: the motion is computed step by step."
                if config.advanced.initial.isTwinActive {
                    summary += " One body was nudged slightly; the faint copy shows the same system without the nudge."
                }
                return summary
            }
            if config.isGalacticCenter {
                return "The star S2 on its observed 16-year orbit around Sagittarius A*, the black hole "
                    + "at the centre of our galaxy, at true scale."
            }
            if config.isBlackHolePlanet {
                return "A rocky planet orbiting a \(config.strongFieldMassLabel) black hole at true scale, "
                    + "far enough out that tides decide whether it survives."
            }
            if config.isStrongField {
                return "A small probe orbiting a \(config.strongFieldMassLabel) black hole only a few times "
                    + "its horizon radius away, at true scale. Here relativity is strong."
            }
            let central = config.isBlackHoleMode ? "a black hole" : "a star"
            let realism = config.isRealistic ? " with real masses and distances" : ""
            return "A planet orbiting \(central)\(realism), following general relativity."
        }

        // MARK: Scale

        var scale: InfoSection {
            var section = InfoSection(id: .scale, title: "What's to Scale")
            if config.isRealistic {
                section.paragraphs.append(
                    "Realistic mode uses real masses, real distances and the real speed of light. "
                    + "The whole system is shrunk to fit the screen, so relativity's effects appear "
                    + "at their true size, which is often far too small to see."
                )
            } else {
                let factor = ScaleComparison.grMagnification(config: config)
                section.paragraphs.append(
                    "Visual mode magnifies relativity so you can see it: orbits turn by degrees and a black "
                    + "hole's horizon is big enough to draw. Masses and distances use familiar units, but "
                    + "the strength of relativity is not real."
                )
                section.facts.append(InfoFact(label: "Relativity magnified", value: "≈ " + RealUnitsFormatter.magnification(factor)))
            }
            section.paragraphs.append(
                "Stars and planets are drawn far larger than life so you can see them. At true scale, "
                + "a planet would be much smaller than a pixel."
            )
            return section
        }

        // MARK: Bodies

        var bodies: InfoSection {
            var section = InfoSection(id: .bodies, title: "The Bodies")
            let labels = snapshot.bodyLabels
            if isThreeBody {
                // Labels read "A 3" or "A 1 M☉": the letter, a space, then the mass.
                for label in labels {
                    section.facts.append(InfoFact(label: "Body \(label.prefix(1))", value: String(label.dropFirst(2))))
                }
                section.paragraphs.append(config.isRealistic
                    ? "Masses are real, in solar masses (M☉) or Earth masses (M⊕)."
                    : "In Visual mode, three-body masses are relative: a body of 4 is twice as heavy as a body of 2.")
                return section
            }
            let roles = twoBodyRoles
            for (role, label) in zip(roles, labels) {
                section.facts.append(InfoFact(label: role, value: label))
            }
            if config.isStrongField && config.strongFieldScenario == .stellarBlackHole {
                section.paragraphs.append(
                    "The probe is a compact test mass: so light compared with the black hole that it doesn't "
                    + "move it, and so small that tides can't tear it apart."
                )
            }
            section.paragraphs.append(
                "Both bodies orbit their common centre of mass. Because the central body is so much heavier, "
                + "it only wobbles slightly around it."
            )
            return section
        }

        private var twoBodyRoles: [String] {
            if config.isGalacticCenter { return ["Black hole", "Star"] }
            if config.isStrongField && config.strongFieldScenario == .stellarBlackHole { return ["Black hole", "Probe"] }
            return [config.isBlackHoleMode ? "Black hole" : "Star", "Planet"]
        }

        // MARK: Black Hole

        var blackHole: InfoSection? {
            guard isBlackHole else { return nil }
            var section = InfoSection(id: .blackHole, title: "The Black Hole")
            let rs = metrics.schwarzschildRadius
            let rsText = text.schwarzschildRadius(metrics)

            section.facts.append(InfoFact(label: "Mass", value: config.isStrongField ? config.strongFieldMassLabel : config.mass1Label))
            section.facts.append(InfoFact(label: "Event horizon " + rsText.label, value: rsText.value))
            section.facts.append(InfoFact(label: "Photon sphere", value: "1.5 r\u{209B}"))
            section.facts.append(InfoFact(label: "ISCO", value: "3 r\u{209B}"))
            if metrics.separation > 0 && !metrics.isAbsorbed {
                section.facts.append(InfoFact(label: "Distance", value: distanceText(metrics.separation)))
                if rs > 0 {
                    section.facts.append(InfoFact(label: "Distance ÷ horizon", value: Self.ratioText(metrics.separation / rs) + "×"))
                }
            }
            section.facts.append(InfoFact(label: "Horizon on screen", value: Self.pointsText(rs * snapshot.coordinateScale)))

            section.paragraphs.append(
                "The event horizon is the point of no return: inside it, nothing can escape, not even light. "
                + "Its radius, rₛ = 2GM/c², grows in proportion to the mass."
            )
            section.paragraphs.append(
                "At the photon sphere (1.5 rₛ) light itself can circle the hole. Inside the ISCO (3 rₛ), "
                + "the innermost stable circular orbit, no orbit lasts: anything closer spirals in."
            )
            section.paragraphs.append(sizeExplanation)

            if config.isBlackHolePlanet {
                let roche = config.blackHolePlanetRocheLimitRs
                section.facts.append(InfoFact(label: "Roche limit", value: SimulationConfig.groupedInteger(roche) + " r\u{209B}"))
                section.paragraphs.append(
                    "Tides stretch the planet: its near side is pulled harder than its far side. Inside the Roche "
                    + "limit that stretch beats the planet's own gravity and tears it apart. The limit barely "
                    + "depends on the planet's mass, because a heavier rocky planet is also bigger."
                )
            } else if config.isGalacticCenter {
                section.paragraphs.append(
                    "S2 never comes closer than about 1,400 rₛ, but it moves fast enough there for relativity to "
                    + "turn its orbit by about 12′ (arcminutes) each time. The GRAVITY collaboration measured this "
                    + "in 2020, in agreement with general relativity."
                )
            }
            section.paragraphs.append("The glowing disk around the hole is an illustration; it isn't simulated.")
            return section
        }

        /// Why the horizon looks the size it does.
        private var sizeExplanation: String {
            let rs = metrics.schwarzschildRadius
            let onScreen = rs * snapshot.coordinateScale
            guard config.isRealistic else {
                let realKm = 2 * SIConstants.solarGravitationalLength * config.mass1Multiplier / SIConstants.kilometer
                let factor = ScaleComparison.grMagnification(config: config)
                return "In Visual mode the horizon is drawn about \(RealUnitsFormatter.magnification(factor)) "
                    + "larger, compared with the orbit, than it really is. A real black hole of "
                    + "\(config.mass1Label) has a horizon only \(String(format: "%.3g", realKm)) km in radius."
            }
            let ratio = metrics.separation > 0 && rs > 0 ? metrics.separation / rs : 0
            var explanation = "Here the horizon is drawn at its true size compared with the orbit."
            if ratio > 0 {
                explanation += " The orbiting body is about \(Self.ratioText(ratio)) times the horizon's radius away"
                explanation += onScreen < 1
                    ? ", so the horizon is far smaller than a pixel: that's why you can't see the black hole itself."
                    : ", so the horizon is \(Self.pointsText(onScreen)) across on screen."
            }
            return explanation
        }

        private func distanceText(_ length: Double) -> String {
            if config.isStrongField { return config.distanceLabel(simulationLength: length) }
            return String(format: "%.2f AU", length / config.scale.au)
        }

        // MARK: Habitable Zone

        var habitableZone: InfoSection? {
            guard !isThreeBody, let zone = snapshot.habitableZone else { return nil }
            let settings = config.advanced.habitableZone
            let limits = settings.limits
            var section = InfoSection(id: .habitableZone, title: "The Habitable Zone")

            section.paragraphs.append(
                "The green band is the range of distances where a planet like Earth could keep liquid water "
                + "on its surface: not too hot, not too cold."
            )
            if config.isBlackHoleMode {
                section.paragraphs.append(
                    "A black hole gives off no light itself, but the gas spiralling into it glows. The zone uses "
                    + "that accretion disk's brightness, set as a fraction of the Eddington limit, the brightest "
                    + "a disk can shine."
                )
                section.facts.append(InfoFact(label: "Accretion", value: config.accretionLabel + " of Eddington"))
            } else {
                section.paragraphs.append(
                    "Its position depends on how bright the star is. The app estimates the brightness from the "
                    + "star's mass, with the main-sequence mass–luminosity relation (about L ∝ M⁴ for Sun-like stars)."
                )
            }
            section.facts.append(InfoFact(label: "Brightness", value: RealUnitsFormatter.scientific(zone.luminosity) + " L\u{2609}"))

            section.paragraphs.append(
                "The edges are where the planet would get a set amount of light compared with Earth: "
                + "\(Self.fluxText(limits.innerFlux))× Earth's sunlight at the hot inner edge and "
                + "\(Self.fluxText(limits.outerFlux))× at the cold outer edge. Light fades with the square of "
                + "distance, so each edge sits at d = √(L ÷ flux), in AU for L in solar luminosities."
            )
            section.facts.append(InfoFact(label: "Limits", value: "\(limits.displayName) (\(Self.source(of: limits)))"))
            section.facts.append(InfoFact(label: "Inner edge", value: String(format: "%.2f AU", zone.innerAU)))
            section.facts.append(InfoFact(label: "Outer edge", value: String(format: "%.2f AU", zone.outerAU)))

            if let temperature = snapshot.planetEquilibriumTemperature, let status = snapshot.habitableStatus {
                section.facts.append(InfoFact(
                    label: twoBodyRoles[1], value: "\(status.label) · \(String(format: "%.0f", temperature)) K"
                ))
                section.facts.append(InfoFact(label: "Albedo", value: String(format: "%.2f", settings.bondAlbedo)))
                section.paragraphs.append(
                    "The temperature is the planet's equilibrium temperature: how warm it gets from the light it "
                    + "absorbs, after reflecting a fraction of it (its albedo). It ignores any greenhouse effect, "
                    + "which is why Earth would read about 255 K instead of its real 288 K."
                )
            }
            if snapshot.isHabitableZoneOffScreen {
                section.paragraphs.append(
                    "The zone is beyond the edge of the view right now: a brighter body pushes it further out."
                )
            }
            return section
        }

        private static func fluxText(_ flux: Double) -> String {
            String(format: "%g", flux)
        }

        private static func source(of limits: HabitableZoneLimits) -> String {
            switch limits {
            case .conservative: return "Kasting et al. 1993"
            case .optimistic: return "Kopparapu et al. 2013"
            }
        }

        // MARK: Display

        var display: InfoSection {
            var section = InfoSection(id: .display, title: "On the Screen")
            let display = config.advanced.display
            if display.showSpacetimeGrid {
                section.terms.append(InfoTerm(
                    term: "Grid",
                    definition: config.isStrongField
                        ? "Spacetime drawn as a funnel around the black hole (Flamm's paraboloid): deep near the "
                            + "horizon, almost flat far away. A picture only; the physics doesn't use it."
                        : "Dips toward each mass to suggest curved spacetime. A picture only; the physics doesn't use it."
                ))
            }
            section.terms.append(InfoTerm(term: "Trails", definition: "The recent path of each body."))
            if display.showCenterOfMass {
                section.terms.append(InfoTerm(
                    term: "CoM",
                    definition: "The centre of mass: the point every body really orbits. The view stays centred on it."
                ))
            }
            if display.showRelativisticRadii {
                section.terms.append(InfoTerm(term: "Red rings", definition: ringsDefinition))
            }
            if snapshot.habitableZone != nil && !isThreeBody {
                section.terms.append(InfoTerm(term: "Green band", definition: "The habitable zone (see above)."))
            }
            if isThreeBody && config.advanced.initial.isTwinActive {
                section.terms.append(InfoTerm(
                    term: "Ghosts",
                    definition: "The same system without the nudge. \"Twin Δ\" shows how far apart the two have drifted."
                ))
            }
            if display.showVelocityVectors || display.showAccelerationVectors {
                section.terms.append(InfoTerm(term: "Arrows", definition: "Green: velocity. Pink: acceleration."))
            }
            section.terms.append(InfoTerm(term: "Formulas", definition: "The equations behind the motion, top left."))
            return section
        }

        private var ringsDefinition: String {
            if isThreeBody {
                return "Dashed: each body's Schwarzschild radius, how small it would have to be squeezed "
                    + "to become a black hole. Shown only when big enough to see."
            }
            if isBlackHole {
                return "Solid: the event horizon. Dashed: the photon sphere and the ISCO."
            }
            return "Dashed: the star's Schwarzschild radius, how small it would have to be squeezed to become a black hole."
        }

        // MARK: Metrics

        var metricsSection: InfoSection {
            var section = InfoSection(id: .metrics, title: "The Numbers Below")
            if isThreeBody {
                section.terms = [
                    InfoTerm(term: "Time", definition: "Simulated time since the start."),
                    InfoTerm(term: "ΔE/E (GR)", definition: "Change in the total energy since the start. Ideally 0; "
                        + "it drifts with the relativistic correction and the step-by-step calculation. Collisions are excluded."),
                    InfoTerm(term: "Closest r", definition: "The smallest distance between any two bodies so far."),
                    InfoTerm(term: "max v/c", definition: "The highest speed any body has reached, as a fraction of the speed of light."),
                    InfoTerm(term: "Status", definition: "Bound, Ejected (a body escaped for good) or Merged (two bodies collided).")
                ]
                return section
            }
            let orbits = text.orbits(metrics)
            section.terms.append(InfoTerm(
                term: config.isRealistic ? "Elapsed time" : orbits.label,
                definition: config.isRealistic
                    ? "Simulated time since the start, with the number of completed orbits."
                    : "Completed orbits, counted at each closest approach."
            ))
            section.terms.append(InfoTerm(
                term: "τ/t",
                definition: "Time dilation: how fast a clock at the planet's distance ticks compared with one far "
                    + "away. 1 means no slowing; it drops toward 0 near a black hole."
            ))
            section.terms.append(InfoTerm(
                term: "Precession",
                definition: "How far the orbit's closest point has turned in total. Newton predicts none; "
                    + "general relativity predicts a slow turn."
            ))
            section.terms.append(InfoTerm(
                term: "v/c",
                definition: "The orbiting body's speed as a fraction of the speed of light."
            ))
            if isBlackHole {
                section.terms.append(InfoTerm(term: "rₛ", definition: "The black hole's event horizon radius."))
            } else {
                let lorentz = text.lorentz(metrics)
                section.terms.append(InfoTerm(
                    term: lorentz.label,
                    definition: "How much the planet's own clock slows because of its speed (special relativity)."
                ))
            }
            return section
        }

        // MARK: Formatting

        /// A large ratio as "60,000", or "8.0" / "160" for small ones.
        static func ratioText(_ ratio: Double) -> String {
            if ratio >= 1_000 { return SimulationConfig.groupedInteger(ratio) }
            return ratio >= 10 ? String(format: "%.0f", ratio) : String(format: "%.1f", ratio)
        }

        /// A screen length: "under 1 pt", or whole points.
        static func pointsText(_ points: Double) -> String {
            points < 1 ? "under 1 pt" : String(format: "%.0f pt", points)
        }
    }
}
