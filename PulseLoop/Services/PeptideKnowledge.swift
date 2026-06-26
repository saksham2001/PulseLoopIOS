import Foundation

struct PeptideInfo {
    let name: String
    let aliases: [String]
    let category: String
    let defaultDose: String
    let timing: String
    let frequency: String
    let injectionSite: String
    let cycleLength: String
    let benefit: String
    let mechanism: String
    let instructions: String
    let storage: String
    let stackNotes: String
    let warnings: String
    var pros: [String] = []
    var cons: [String] = []
}

struct PeptideStack {
    let name: String
    let aliases: [String]
    let purpose: String
    let peptides: [String]
    let description: String
    let cycleLength: String
    let notes: String
}

enum PeptideKnowledge {

    // MARK: - Individual Peptides

    static let database: [PeptideInfo] = [
        PeptideInfo(
            name: "BPC-157", aliases: ["bpc 157", "body protection compound-157"],
            category: "Healing", defaultDose: "250-500 mcg", timing: "AM",
            frequency: "1-2x daily", injectionSite: "Subcutaneous", cycleLength: "4-12 weeks",
            benefit: "Accelerated tendon and ligament healing",
            mechanism: "Upregulates growth factor expression including VEGF and promotes angiogenesis, modulates nitric oxide system, and interacts with the dopaminergic syst",
            instructions: "Subcutaneous injection or oral",
            storage: "Lyophilized: room temperature. Reconstituted: 2-8°C for up to 30 days.",
            stackNotes: "Tb 500, Ghk Cu, Thymosin Beta 4",
            warnings: "Mild nausea (oral); Injection site irritation"
        ),
        PeptideInfo(
            name: "TB-500", aliases: ["tb 500", "thymosin beta-4 (synthetic)"],
            category: "Healing", defaultDose: "2-5 mg", timing: "AM",
            frequency: "2x per week", injectionSite: "Subcutaneous", cycleLength: "4-8 weeks",
            benefit: "Enhanced wound healing",
            mechanism: "Upregulates actin production to promote cell migration and proliferation, enhances angiogenesis, and reduces pro-inflammatory cytokines.",
            instructions: "Subcutaneous injection",
            storage: "Lyophilized: -20°C long term. Reconstituted: 2-8°C for up to 14 days.",
            stackNotes: "Bpc 157, Ghk Cu, Thymosin Alpha 1",
            warnings: "Headache; Injection site redness"
        ),
        PeptideInfo(
            name: "Pentosan Polysulfate", aliases: ["pentosan polysulfate", "pentosan polysulfate sodium"],
            category: "Healing", defaultDose: "100 mg", timing: "AM",
            frequency: "3x daily (oral)", injectionSite: "Subcutaneous", cycleLength: "3-6 months",
            benefit: "Bladder wall protection",
            mechanism: "Acts as a glycosaminoglycan analog that coats bladder mucosa, inhibits complement activation, and stimulates proteoglycan synthesis in cartilage.",
            instructions: "Oral or subcutaneous injection",
            storage: "Room temperature, protected from moisture.",
            stackNotes: "Bpc 157, Collagen Peptides",
            warnings: "GI upset; Headache"
        ),
        PeptideInfo(
            name: "KPV", aliases: ["kpv", "lysine-proline-valine tripeptide"],
            category: "Healing", defaultDose: "200-500 mcg", timing: "AM",
            frequency: "1-2x daily", injectionSite: "Subcutaneous", cycleLength: "4-8 weeks",
            benefit: "Potent anti-inflammatory",
            mechanism: "Inhibits NF-kB signaling pathway, reduces pro-inflammatory cytokine production (TNF-α, IL-6), and modulates immune cell activation.",
            instructions: "Oral, topical, or subcutaneous",
            storage: "Lyophilized: -20°C. Reconstituted: 2-8°C for up to 21 days.",
            stackNotes: "Bpc 157, Ll 37, Thymosin Alpha 1",
            warnings: "Mild drowsiness; Injection site reaction"
        ),
        PeptideInfo(
            name: "Thymosin Beta-4", aliases: ["thymosin beta 4", "thymosin beta-4 (full length)"],
            category: "Healing", defaultDose: "1-5 mg", timing: "AM",
            frequency: "2-3x per week", injectionSite: "Subcutaneous", cycleLength: "4-12 weeks",
            benefit: "Comprehensive tissue repair",
            mechanism: "Sequesters G-actin to regulate cytoskeleton dynamics, promotes stem cell differentiation, and activates anti-inflammatory and anti-apoptotic pathways.",
            instructions: "Subcutaneous injection",
            storage: "Lyophilized: -20°C. Reconstituted: 2-8°C for up to 14 days.",
            stackNotes: "Bpc 157, Tb 500, Ghk Cu",
            warnings: "Injection site swelling; Temporary fatigue"
        ),
        PeptideInfo(
            name: "LL-37", aliases: ["ll 37", "cathelicidin antimicrobial peptide ll-37"],
            category: "Healing", defaultDose: "50-100 mcg", timing: "AM",
            frequency: "Daily", injectionSite: "Subcutaneous", cycleLength: "2-6 weeks",
            benefit: "Broad-spectrum antimicrobial",
            mechanism: "Disrupts microbial membranes, neutralizes endotoxins, recruits immune cells via chemotaxis, and promotes angiogenesis and re-epithelialization.",
            instructions: "Topical or subcutaneous injection",
            storage: "Lyophilized: -20°C. Reconstituted: 2-8°C, use within 7 days.",
            stackNotes: "Bpc 157, Thymosin Alpha 1, Kpv",
            warnings: "Local irritation; Redness at application site"
        ),
        PeptideInfo(
            name: "AOD-9604", aliases: ["aod 9604", "advanced obesity drug fragment 176-191 (modified)"],
            category: "Weight Management", defaultDose: "300 mcg", timing: "AM",
            frequency: "Daily (morning, fasted)", injectionSite: "Subcutaneous", cycleLength: "12 weeks",
            benefit: "Fat loss without muscle wasting",
            mechanism: "Mimics the lipolytic domain of growth hormone (hGH 176-191), stimulating fat oxidation and inhibiting de novo lipogenesis through pathways independent",
            instructions: "Subcutaneous injection",
            storage: "Lyophilized: 2-8°C. Reconstituted: 2-8°C for up to 30 days.",
            stackNotes: "Cjc 1295, Ipamorelin, Tesamorelin",
            warnings: "Injection site soreness; Headache"
        ),
        PeptideInfo(
            name: "Semaglutide", aliases: ["semaglutide", "semaglutide (glp-1 receptor agonist)"],
            category: "Weight Management", defaultDose: "0.25-2.4 mg", timing: "AM",
            frequency: "Once weekly", injectionSite: "Subcutaneous", cycleLength: "Ongoing",
            benefit: "Significant weight loss (15-17%)",
            mechanism: "Binds GLP-1 receptors in the pancreas to stimulate insulin secretion, in the brain to reduce appetite, and in the GI tract to slow gastric emptying. 9",
            instructions: "Subcutaneous",
            storage: "Refrigerated 2-8°C. In-use pen: room temperature up to 56 days.",
            stackNotes: "Tirzepatide, Tesamorelin, 5 Amino 1Mq",
            warnings: "Nausea and vomiting; Diarrhea or constipation"
        ),
        PeptideInfo(
            name: "Tirzepatide", aliases: ["tirzepatide", "tirzepatide (dual gip/glp-1 receptor agonist)"],
            category: "Weight Management", defaultDose: "2.5-15 mg", timing: "AM",
            frequency: "Once weekly", injectionSite: "Subcutaneous", cycleLength: "Ongoing",
            benefit: "Superior weight loss (20-25%)",
            mechanism: "Activates both GIP and GLP-1 receptors simultaneously for synergistic effects on insulin secretion, appetite reduction, and fat metabolism. GIP activa",
            instructions: "Subcutaneous",
            storage: "Refrigerated 2-8°C. Single-use pens.",
            stackNotes: "Semaglutide, Tesamorelin, Mots C",
            warnings: "Nausea (most common); Diarrhea"
        ),
        PeptideInfo(
            name: "Retatrutide", aliases: ["retatrutide", "retatrutide (triple agonist gip/glp-1/glucagon)"],
            category: "Weight Management", defaultDose: "1-12 mg", timing: "AM",
            frequency: "Once weekly", injectionSite: "Subcutaneous", cycleLength: "Ongoing",
            benefit: "Unprecedented weight loss (~24%)",
            mechanism: "Triple agonism creates synergistic metabolic effects. Glucagon activation increases energy expenditure and hepatic fat oxidation while GLP-1/GIP reduc",
            instructions: "Subcutaneous",
            storage: "Refrigerated 2-8°C.",
            stackNotes: "Mots C, 5 Amino 1Mq",
            warnings: "GI effects (nausea, diarrhea, vomiting); Decreased appetite"
        ),
        PeptideInfo(
            name: "Tesofensine", aliases: ["tesofensine", "tesofensine (triple monoamine reuptake inhibitor)"],
            category: "Weight Management", defaultDose: "0.25-0.5 mg", timing: "AM",
            frequency: "Once daily", injectionSite: "Oral", cycleLength: "24+ weeks",
            benefit: "Significant appetite reduction",
            mechanism: "Blocks presynaptic reuptake of noradrenaline, dopamine, and serotonin in the hypothalamus, enhancing satiety signaling, reducing food reward, and incr",
            instructions: "Oral",
            storage: "Room temperature, protected from light and moisture.",
            stackNotes: "Semaglutide, Aod 9604, 5 Amino 1Mq",
            warnings: "Dry mouth; Insomnia"
        ),
        PeptideInfo(
            name: "CagriSema", aliases: ["cagrisema", "cagrisema (cagrilintide + semaglutide)"],
            category: "Weight Management", defaultDose: "Cagrilintide 2.4mg + Semaglutide 2.4mg", timing: "AM",
            frequency: "Once weekly", injectionSite: "Subcutaneous", cycleLength: "Ongoing",
            benefit: "Enhanced weight loss vs monotherapy",
            mechanism: "Dual-pathway activation: cagrilintide mimics amylin to activate area postrema satiety centers, while semaglutide activates GLP-1 receptors for complem",
            instructions: "Subcutaneous",
            storage: "Refrigerated 2-8°C.",
            stackNotes: "Mots C, 5 Amino 1Mq, Tesamorelin",
            warnings: "Nausea; Vomiting"
        ),
        PeptideInfo(
            name: "Survodutide", aliases: ["survodutide", "survodutide (dual glp-1/glucagon agonist)"],
            category: "Weight Management", defaultDose: "0.6-6.0 mg", timing: "AM",
            frequency: "Once weekly", injectionSite: "Subcutaneous", cycleLength: "Ongoing",
            benefit: "Significant weight loss (up to 19%)",
            mechanism: "Activates GLP-1 receptors to reduce appetite while glucagon receptor activation increases hepatic fat oxidation, energy expenditure, and amino acid ca",
            instructions: "Subcutaneous",
            storage: "Refrigerated 2-8°C.",
            stackNotes: "Mots C, 5 Amino 1Mq",
            warnings: "Nausea; Diarrhea"
        ),
        PeptideInfo(
            name: "Orforglipron", aliases: ["orforglipron", "orforglipron (oral non-peptide glp-1 agonist)"],
            category: "Weight Management", defaultDose: "12-45 mg", timing: "AM",
            frequency: "Once daily", injectionSite: "Oral", cycleLength: "Ongoing",
            benefit: "Oral administration (no injection)",
            mechanism: "Small molecule agonist of GLP-1 receptors that mimics native GLP-1 binding without requiring peptide structure. Achieves full receptor activation with",
            instructions: "Oral",
            storage: "Room temperature, protected from moisture.",
            stackNotes: "Mots C, 5 Amino 1Mq, Tesamorelin",
            warnings: "Nausea (dose-dependent); Vomiting"
        ),
        PeptideInfo(
            name: "Liraglutide", aliases: ["liraglutide", "liraglutide (glp-1 receptor agonist / saxenda)"],
            category: "Weight Management", defaultDose: "0.6-3.0 mg", timing: "AM",
            frequency: "Once daily", injectionSite: "Subcutaneous", cycleLength: "Ongoing",
            benefit: "Proven weight loss (5-10%)",
            mechanism: "Binds and activates the GLP-1 receptor, enhancing glucose-dependent insulin secretion, suppressing glucagon, slowing gastric emptying, and reducing ap",
            instructions: "Subcutaneous",
            storage: "Refrigerated 2-8°C. In-use: room temperature up to 30 days.",
            stackNotes: "Aod 9604, Tesamorelin, Mots C",
            warnings: "Nausea; Vomiting"
        ),
        PeptideInfo(
            name: "Mazdutide", aliases: ["mazdutide", "mazdutide (dual glp-1/glucagon agonist)"],
            category: "Weight Management", defaultDose: "3-9 mg", timing: "AM",
            frequency: "Once weekly", injectionSite: "Subcutaneous", cycleLength: "Ongoing",
            benefit: "Significant weight loss (up to 18%)",
            mechanism: "Dual activation of GLP-1 receptors for appetite suppression combined with glucagon receptor activation for enhanced hepatic lipid oxidation and energy",
            instructions: "Subcutaneous",
            storage: "Refrigerated 2-8°C.",
            stackNotes: "Mots C, 5 Amino 1Mq",
            warnings: "Nausea; Diarrhea"
        ),
        PeptideInfo(
            name: "MOTS-c", aliases: ["mots c", "mitochondrial open reading frame of the 12s rrna-c"],
            category: "Weight Management", defaultDose: "5-10 mg", timing: "AM",
            frequency: "3-5x per week", injectionSite: "Subcutaneous", cycleLength: "8-12 weeks",
            benefit: "Exercise mimetic effects",
            mechanism: "Activates AMPK pathway, enhances mitochondrial metabolism, improves insulin sensitivity by increasing GLUT4 translocation, and promotes fatty acid oxi",
            instructions: "Subcutaneous",
            storage: "Lyophilized: -20°C. Reconstituted: 2-8°C for 14 days.",
            stackNotes: "5 Amino 1Mq, Semaglutide, Aod 9604",
            warnings: "Injection site reactions; Mild hypoglycemia (with exercise)"
        ),
        PeptideInfo(
            name: "5-Amino-1MQ", aliases: ["5 amino 1mq", "5-amino-1-methylquinolinium (nnmt inhibitor)"],
            category: "Weight Management", defaultDose: "50-100 mg", timing: "AM",
            frequency: "1-2x daily", injectionSite: "Oral", cycleLength: "8-12 weeks",
            benefit: "Increased cellular energy metabolism",
            mechanism: "Inhibits NNMT enzyme, preventing methylation and degradation of nicotinamide. Increases intracellular NAD+ pools, activates sirtuins, and reduces fat ",
            instructions: "Oral (capsule)",
            storage: "Room temperature, protected from light and moisture.",
            stackNotes: "Mots C, Semaglutide, Aod 9604",
            warnings: "Mild GI discomfort; Headache (rare)"
        ),
        PeptideInfo(
            name: "HGH Fragment 176-191", aliases: ["hgh fragment 176 191", "human growth hormone fragment 176-191"],
            category: "Weight Management", defaultDose: "250-500 mcg", timing: "AM",
            frequency: "1-2x daily", injectionSite: "Subcutaneous", cycleLength: "8-12 weeks",
            benefit: "Targeted fat loss",
            mechanism: "Mimics lipolytic action of HGH by stimulating beta-3 adrenergic receptors on adipocytes, increasing cyclic AMP and hormone-sensitive lipase activity. ",
            instructions: "Subcutaneous",
            storage: "Lyophilized: -20°C. Reconstituted: 2-8°C for 21 days.",
            stackNotes: "Aod 9604, Cjc 1295, Ipamorelin",
            warnings: "Injection site irritation; Mild headache"
        ),
        PeptideInfo(
            name: "CJC-1295", aliases: ["cjc 1295", "cjc-1295 (modified grf 1-29)"],
            category: "GH Secretagogue", defaultDose: "100-300 mcg (no DAC) / 2mg (with DAC)", timing: "AM",
            frequency: "1-3x daily (no DAC) / 2x weekly (DAC)", injectionSite: "Subcutaneous", cycleLength: "8-16 weeks",
            benefit: "Increased GH production",
            mechanism: "Binds GHRH receptors on anterior pituitary somatotrophs, stimulating cAMP-dependent GH synthesis and pulsatile release.",
            instructions: "Subcutaneous",
            storage: "Lyophilized: -20°C. Reconstituted: 2-8°C for 21 days.",
            stackNotes: "Ipamorelin, Ghrp 2, Ghrp 6",
            warnings: "Flushing; Headache"
        ),
        PeptideInfo(
            name: "Ipamorelin", aliases: ["ipamorelin", "ipamorelin (selective gh secretagogue)"],
            category: "GH Secretagogue", defaultDose: "100-300 mcg", timing: "AM",
            frequency: "2-3x daily", injectionSite: "Subcutaneous", cycleLength: "8-16 weeks",
            benefit: "Clean GH release",
            mechanism: "Selectively activates GHSR on pituitary somatotrophs. Unlike GHRP-6 and hexarelin, does not significantly activate ACTH or prolactin-releasing pathway",
            instructions: "Subcutaneous",
            storage: "Lyophilized: -20°C. Reconstituted: 2-8°C for 28 days.",
            stackNotes: "Cjc 1295, Tesamorelin, Bpc 157",
            warnings: "Mild hunger increase; Head rush post-injection"
        ),
        PeptideInfo(
            name: "MK-677 (Ibutamoren)", aliases: ["mk 677", "ibutamoren mesylate (mk-677)"],
            category: "GH Secretagogue", defaultDose: "10-25 mg", timing: "AM",
            frequency: "Once daily", injectionSite: "Oral", cycleLength: "12-24 weeks (cycle)",
            benefit: "Oral administration",
            mechanism: "Acts as ghrelin mimetic at GHS-R1a receptors in hypothalamus and pituitary. Excellent oral bioavailability and 24-hour duration.",
            instructions: "Oral",
            storage: "Room temperature, protected from light.",
            stackNotes: "Cjc 1295, Ipamorelin",
            warnings: "Increased appetite; Water retention/edema"
        ),
        PeptideInfo(
            name: "Sermorelin", aliases: ["sermorelin", "sermorelin acetate (ghrh 1-29)"],
            category: "GH Secretagogue", defaultDose: "200-300 mcg", timing: "AM",
            frequency: "Once daily (before bed)", injectionSite: "Subcutaneous", cycleLength: "3-6 months",
            benefit: "Natural GH pulsatility preserved",
            mechanism: "Binds GHRH receptors on anterior pituitary via cAMP-PKA pathway. Preserves natural feedback regulation and pulsatility unlike exogenous HGH.",
            instructions: "Subcutaneous",
            storage: "Lyophilized: 2-8°C. Reconstituted: 2-8°C for 14 days.",
            stackNotes: "Ipamorelin, Ghrp 2, Ghrp 6",
            warnings: "Injection site reaction; Flushing"
        ),
        PeptideInfo(
            name: "Tesamorelin", aliases: ["tesamorelin", "tesamorelin acetate (egrifta)"],
            category: "GH Secretagogue", defaultDose: "2 mg", timing: "AM",
            frequency: "Once daily", injectionSite: "Subcutaneous", cycleLength: "12-26 weeks",
            benefit: "Visceral fat reduction (up to 18%)",
            mechanism: "Binds pituitary GHRH receptors with enhanced affinity via hexenoic acid modification. Effective at mobilizing visceral fat via GH-mediated lipolysis.",
            instructions: "Subcutaneous",
            storage: "Lyophilized: refrigerated. Reconstituted: use immediately.",
            stackNotes: "Ipamorelin, Cjc 1295, Mots C",
            warnings: "Injection site reactions; Joint pain"
        ),
        PeptideInfo(
            name: "GHRP-2", aliases: ["ghrp 2", "growth hormone releasing peptide-2 (pralmorelin)"],
            category: "GH Secretagogue", defaultDose: "100-300 mcg", timing: "AM",
            frequency: "2-3x daily", injectionSite: "Subcutaneous", cycleLength: "8-12 weeks",
            benefit: "Strongest GH release among GHRPs",
            mechanism: "Potent GHSR-1a agonist stimulating GH release and appetite. Also mildly stimulates ACTH/cortisol release.",
            instructions: "Subcutaneous",
            storage: "Lyophilized: -20°C. Reconstituted: 2-8°C for 21 days.",
            stackNotes: "Cjc 1295, Sermorelin, Tesamorelin",
            warnings: "Increased appetite (significant); Cortisol elevation (mild)"
        ),
        PeptideInfo(
            name: "GHRP-6", aliases: ["ghrp 6", "growth hormone releasing peptide-6"],
            category: "GH Secretagogue", defaultDose: "100-300 mcg", timing: "AM",
            frequency: "2-3x daily", injectionSite: "Subcutaneous", cycleLength: "8-12 weeks",
            benefit: "Strong GH release",
            mechanism: "Activates GHSR-1a on pituitary for GH release and hypothalamic neurons for appetite. Triggers gastric motility and ghrelin-like reward signaling.",
            instructions: "Subcutaneous",
            storage: "Lyophilized: -20°C. Reconstituted: 2-8°C for 21 days.",
            stackNotes: "Cjc 1295, Sermorelin, Bpc 157",
            warnings: "Intense hunger; Cortisol elevation"
        ),
        PeptideInfo(
            name: "Hexarelin", aliases: ["hexarelin", "hexarelin (examorelin)"],
            category: "GH Secretagogue", defaultDose: "100-200 mcg", timing: "AM",
            frequency: "2-3x daily", injectionSite: "Subcutaneous", cycleLength: "4-8 weeks (then break)",
            benefit: "Strongest GH release",
            mechanism: "Potent GHSR-1a agonist producing maximal pituitary GH output. Additionally binds cardiac CD36, providing cardioprotection through anti-apoptotic mecha",
            instructions: "Subcutaneous",
            storage: "Lyophilized: -20°C. Reconstituted: 2-8°C.",
            stackNotes: "Cjc 1295, Sermorelin",
            warnings: "Cortisol/prolactin increase; Rapid desensitization"
        ),
        PeptideInfo(
            name: "CJC-1295 DAC", aliases: ["cjc 1295 dac", "cjc-1295 with drug affinity complex"],
            category: "GH Secretagogue", defaultDose: "2 mg", timing: "AM",
            frequency: "1-2x per week", injectionSite: "Subcutaneous", cycleLength: "8-16 weeks",
            benefit: "Once/twice weekly dosing",
            mechanism: "The DAC moiety binds serum albumin creating a depot that slowly releases active CJC-1295 for continuous GHRH signaling.",
            instructions: "Subcutaneous",
            storage: "Lyophilized: -20°C. Reconstituted: 2-8°C for 21 days.",
            stackNotes: "Mk 677, Ipamorelin",
            warnings: "Water retention; Tingling/numbness"
        ),
        PeptideInfo(
            name: "Copper Peptides", aliases: ["copper peptides", "copper peptide complex (ahk-cu, ghk-cu variants)"],
            category: "Skin & Anti-Aging", defaultDose: "1-3% topical solution", timing: "AM",
            frequency: "1-2x daily", injectionSite: "Topical", cycleLength: "12+ weeks",
            benefit: "Collagen stimulation",
            mechanism: "Copper peptides deliver bioavailable copper to tissues while the peptide provides signaling to stimulate collagen I/III synthesis, attract immune cell",
            instructions: "Topical",
            storage: "Cool, dark place. Solution stable 6+ months refrigerated.",
            stackNotes: "Ghk Cu, Matrixyl, Collagen Peptides",
            warnings: "Skin irritation (sensitive skin); Green-blue discoloration if overused"
        ),
        PeptideInfo(
            name: "Matrixyl", aliases: ["matrixyl", "matrixyl (palmitoyl pentapeptide-4 / pal-kttks)"],
            category: "Skin & Anti-Aging", defaultDose: "2-8% in serum/cream", timing: "AM",
            frequency: "1-2x daily", injectionSite: "Topical", cycleLength: "8-12 weeks for visible results",
            benefit: "Stimulates collagen I, III, IV",
            mechanism: "Signals through TGF-B pathway to stimulate fibroblast production of collagen I, III, IV, fibronectin, and hyaluronic acid. Palmitoyl chain enhances pe",
            instructions: "Topical",
            storage: "Room temperature, protected from direct sunlight.",
            stackNotes: "Ghk Cu, Argireline, Palmitoyl Tripeptide 1",
            warnings: "Rarely irritating; Possible mild tingling"
        ),
        PeptideInfo(
            name: "Argireline", aliases: ["argireline", "argireline (acetyl hexapeptide-3)"],
            category: "Skin & Anti-Aging", defaultDose: "5-10% solution", timing: "AM",
            frequency: "2x daily", injectionSite: "Topical", cycleLength: "4-8 weeks for initial results",
            benefit: "Reduces expression wrinkles up to 30%",
            mechanism: "Competes with SNAP-25 for position in SNARE complex, partially inhibiting vesicle docking and neurotransmitter release, reducing muscle contraction in",
            instructions: "Topical",
            storage: "Room temperature, protected from heat.",
            stackNotes: "Matrixyl, Leuphasyl, Snap 8",
            warnings: "Mild tingling; Rare skin sensitivity"
        ),
        PeptideInfo(
            name: "Leuphasyl", aliases: ["leuphasyl", "leuphasyl (pentapeptide-18)"],
            category: "Skin & Anti-Aging", defaultDose: "3-5% solution", timing: "AM",
            frequency: "2x daily", injectionSite: "Topical", cycleLength: "4-8 weeks",
            benefit: "Complements argireline action",
            mechanism: "Binds enkephalin receptors on neuronal membranes, reducing calcium influx and neurotransmitter release at the presynaptic level. Works upstream of arg",
            instructions: "Topical",
            storage: "Room temperature, away from light.",
            stackNotes: "Argireline, Snap 8, Matrixyl",
            warnings: "Minimal side effects; Rare tingling"
        ),
        PeptideInfo(
            name: "SNAP-8", aliases: ["snap 8", "snap-8 (acetyl octapeptide-3)"],
            category: "Skin & Anti-Aging", defaultDose: "3-10% solution", timing: "AM",
            frequency: "2x daily", injectionSite: "Topical", cycleLength: "4-8 weeks",
            benefit: "Superior to argireline",
            mechanism: "More effectively competes with SNAP-25 for SNARE complex incorporation due to longer sequence, providing greater vesicle-membrane fusion inhibition.",
            instructions: "Topical",
            storage: "Room temperature, protect from UV.",
            stackNotes: "Argireline, Leuphasyl, Matrixyl",
            warnings: "Minimal side effects; Rare irritation on sensitive skin"
        ),
        PeptideInfo(
            name: "Palmitoyl Tripeptide-1", aliases: ["palmitoyl tripeptide 1", "palmitoyl tripeptide-1 (pal-ghk)"],
            category: "Skin & Anti-Aging", defaultDose: "2-5% in formulation", timing: "AM",
            frequency: "1-2x daily", injectionSite: "Topical", cycleLength: "8-16 weeks",
            benefit: "Collagen synthesis stimulation",
            mechanism: "Functions as matrikine signal, mimicking collagen fragments that trigger fibroblasts to produce new collagen. Palmitoyl enables deeper skin penetratio",
            instructions: "Topical",
            storage: "Room temperature, stable in formulation.",
            stackNotes: "Palmitoyl Tetrapeptide 7, Matrixyl, Ghk Cu",
            warnings: "Very well tolerated; Rare irritation"
        ),
        PeptideInfo(
            name: "Palmitoyl Tetrapeptide-7", aliases: ["palmitoyl tetrapeptide 7", "palmitoyl tetrapeptide-7 (pal-gqpr)"],
            category: "Skin & Anti-Aging", defaultDose: "2-4% in formulation", timing: "AM",
            frequency: "1-2x daily", injectionSite: "Topical", cycleLength: "8-16 weeks",
            benefit: "Anti-inflammatory (skin)",
            mechanism: "Inhibits IL-6 release from keratinocytes and reduces inflammation-mediated MMP activation, preserving existing collagen while complementing Pal-GHK co",
            instructions: "Topical",
            storage: "Room temperature, stable in formulations.",
            stackNotes: "Palmitoyl Tripeptide 1, Argireline, Ghk Cu",
            warnings: "Extremely well tolerated; No significant reports"
        ),
        PeptideInfo(
            name: "Acetyl Hexapeptide-8", aliases: ["acetyl hexapeptide 8", "acetyl hexapeptide-8 (argireline advanced)"],
            category: "Skin & Anti-Aging", defaultDose: "5-10%", timing: "AM",
            frequency: "2x daily", injectionSite: "Topical", cycleLength: "4-8 weeks",
            benefit: "Improved stability",
            mechanism: "Same SNARE complex competition as argireline with acetyl modification for improved stability and cellular uptake.",
            instructions: "Topical",
            storage: "Room temperature, protect from oxidation.",
            stackNotes: "Leuphasyl, Snap 8, Matrixyl",
            warnings: "Mild tingling (rare); Sensitivity in some skin types"
        ),
        PeptideInfo(
            name: "Collagen Peptides", aliases: ["collagen peptides", "hydrolyzed collagen peptides (types i, ii, iii)"],
            category: "Skin & Anti-Aging", defaultDose: "5-15 g", timing: "AM",
            frequency: "Once daily", injectionSite: "Oral", cycleLength: "8-12 weeks minimum",
            benefit: "Improved skin elasticity/hydration",
            mechanism: "Absorbed as di/tripeptides (Pro-Hyp, Hyp-Gly), accumulate in skin and signal fibroblasts to increase collagen, hyaluronic acid, and elastin production",
            instructions: "Oral (powder/capsule)",
            storage: "Room temperature, dry, sealed container.",
            stackNotes: "Ghk Cu, Matrixyl, Palmitoyl Tripeptide 1",
            warnings: "Mild bloating (initial); Unpleasant taste (some)"
        ),
        PeptideInfo(
            name: "Elastin Peptides", aliases: ["elastin peptides", "hydrolyzed elastin peptides"],
            category: "Skin & Anti-Aging", defaultDose: "1-5% topical or 2-5g oral", timing: "AM",
            frequency: "Daily", injectionSite: "Topical", cycleLength: "12+ weeks",
            benefit: "Improved skin elasticity",
            mechanism: "Elastin-derived peptides bind the elastin receptor complex (S-Gal) on fibroblasts, triggering tropoelastin production and elastic fiber assembly.",
            instructions: "Topical or Oral",
            storage: "Room temperature, dry storage.",
            stackNotes: "Collagen Peptides, Ghk Cu, Matrixyl",
            warnings: "Well tolerated; Rare irritation (topical)"
        ),
        PeptideInfo(
            name: "Silk Peptides", aliases: ["silk peptides", "hydrolyzed silk fibroin peptides"],
            category: "Skin & Anti-Aging", defaultDose: "1-5% topical or 2-5g oral", timing: "AM",
            frequency: "Daily", injectionSite: "Topical", cycleLength: "8-12 weeks",
            benefit: "Intense hydration",
            mechanism: "Form hydrogen-bonded films on skin for moisture retention. Absorbed peptides provide substrates for keratin/collagen synthesis. Exhibit antioxidant an",
            instructions: "Topical or Oral",
            storage: "Room temperature, protect from humidity.",
            stackNotes: "Collagen Peptides, Ghk Cu, Matrixyl",
            warnings: "Well tolerated; Silk allergy possible (rare)"
        ),
        PeptideInfo(
            name: "GHK-Cu", aliases: ["ghk cu", "copper peptide ghk-cu (glycyl-histidyl-lysine copper)"],
            category: "Skin & Anti-Aging", defaultDose: "1-3 mg topical or 200-500 mcg injectable", timing: "AM",
            frequency: "Daily (topical) or 3x/week (injectable)", injectionSite: "Subcutaneous", cycleLength: "8-12 weeks",
            benefit: "Collagen and elastin synthesis",
            mechanism: "Copper delivery enhances antioxidant enzyme activity (SOD), stimulates collagen and glycosaminoglycan synthesis, promotes stem cell activation, and mo",
            instructions: "Topical cream/serum or subcutaneous injection",
            storage: "Topical: room temperature, protect from light. Injectable: 2-8°C reconstituted.",
            stackNotes: "Bpc 157, Matrixyl, Collagen Peptides",
            warnings: "Skin irritation (topical); Injection site bruising"
        ),
        PeptideInfo(
            name: "Epithalon", aliases: ["epithalon", "epithalon (epitalon / epithalone)"],
            category: "Anti-Aging", defaultDose: "5-10 mg", timing: "AM",
            frequency: "Daily for 10-20 days", injectionSite: "Subcutaneous", cycleLength: "10-20 day cycles, 2-3x per year",
            benefit: "Telomerase activation",
            mechanism: "Activates telomerase reverse transcriptase (hTERT) expression for telomere maintenance. Also normalizes circadian rhythm via melatonin regulation and ",
            instructions: "Subcutaneous",
            storage: "Lyophilized: -20°C. Reconstituted: 2-8°C for 14 days.",
            stackNotes: "Nad Plus, Humanin, Ss 31",
            warnings: "Injection site reaction; Drowsiness"
        ),
        PeptideInfo(
            name: "NAD+", aliases: ["nad plus", "nicotinamide adenine dinucleotide (nad+ / nmn / nr)"],
            category: "Anti-Aging", defaultDose: "250-500mg IV or 500-1000mg NMN oral", timing: "AM",
            frequency: "Weekly (IV) or Daily (oral)", injectionSite: "Oral", cycleLength: "Ongoing",
            benefit: "Restored cellular energy",
            mechanism: "NAD+ serves as cofactor for sirtuins (SIRT1-7), PARPs (DNA repair), and CD38. Declining NAD+ impairs mitochondrial function and epigenetic maintenance",
            instructions: "IV infusion or Oral (precursors)",
            storage: "NMN/NR: cool, dry, sealed. NAD+ solution: refrigerated.",
            stackNotes: "Epithalon, Humanin, Ss 31",
            warnings: "Flushing (IV); Nausea"
        ),
        PeptideInfo(
            name: "Humanin", aliases: ["humanin", "humanin (hn) mitochondrial-derived peptide"],
            category: "Anti-Aging", defaultDose: "1-5 mg", timing: "AM",
            frequency: "3-5x per week", injectionSite: "Subcutaneous", cycleLength: "8-12 weeks",
            benefit: "Neuroprotection against amyloid-beta",
            mechanism: "Binds IGFBP-3, BAX, and trimeric receptor (CNTFR/WSX-1/gp130) to activate STAT3. Inhibits mitochondrial apoptosis and provides neuroprotection.",
            instructions: "Subcutaneous",
            storage: "Lyophilized: -20°C. Reconstituted: 2-8°C.",
            stackNotes: "Epithalon, Nad Plus, Mots C",
            warnings: "Injection site reactions; Mild fatigue (initial)"
        ),
        PeptideInfo(
            name: "FOXO4-DRI", aliases: ["foxo4 dri", "foxo4-d-retro-inverso peptide (senolytic)"],
            category: "Anti-Aging", defaultDose: "5-10 mg/kg (animal studies)", timing: "AM",
            frequency: "3x per week for 3 weeks", injectionSite: "Subcutaneous", cycleLength: "3-week cycles",
            benefit: "Selective senescent cell elimination",
            mechanism: "Competitively disrupts FOXO4 sequestration of p53 in senescent cells, releasing p53 to trigger intrinsic apoptosis selectively in cells relying on thi",
            instructions: "Subcutaneous",
            storage: "Lyophilized: -20°C. Light-sensitive.",
            stackNotes: "Epithalon, Nad Plus, Ss 31",
            warnings: "Limited human safety data; Transient inflammatory response possible"
        ),
        PeptideInfo(
            name: "SS-31 (Elamipretide)", aliases: ["ss 31", "ss-31 / elamipretide (bendavia)"],
            category: "Anti-Aging", defaultDose: "5-40 mg", timing: "AM",
            frequency: "Daily", injectionSite: "Subcutaneous", cycleLength: "4-12 weeks",
            benefit: "Mitochondrial function optimization",
            mechanism: "Targets cardiolipin in inner mitochondrial membrane, stabilizes cytochrome c binding, optimizes electron transfer efficiency, and reduces mitochondria",
            instructions: "Subcutaneous or IV",
            storage: "Lyophilized: -20°C. Solution: 2-8°C.",
            stackNotes: "Nad Plus, Mots C, Humanin",
            warnings: "Injection site reactions; Headache"
        ),
        PeptideInfo(
            name: "GDF-11", aliases: ["gdf 11", "growth differentiation factor 11"],
            category: "Anti-Aging", defaultDose: "0.1-0.5 mg/kg (research)", timing: "AM",
            frequency: "Daily (animal studies)", injectionSite: "Subcutaneous", cycleLength: "4-8 weeks",
            benefit: "Potential tissue rejuvenation",
            mechanism: "Signals through activin type II receptors and SMAD2/3 to restore stem cell function, promote neurogenesis, and improve vascular remodeling in the cont",
            instructions: "Subcutaneous",
            storage: "Lyophilized: -80°C long term. Aliquots at -20°C.",
            stackNotes: "Epithalon, Humanin, Nad Plus",
            warnings: "Limited safety data; Theoretical cancer risk (TGF-B)"
        ),
        PeptideInfo(
            name: "Thymosin Alpha-1", aliases: ["thymosin alpha 1", "thymosin alpha-1 (thymalfasin)"],
            category: "Immune", defaultDose: "1.6-3.2 mg", timing: "AM",
            frequency: "2-3x per week", injectionSite: "Subcutaneous", cycleLength: "4-12 weeks or longer",
            benefit: "Enhanced T-cell immunity",
            mechanism: "Activates toll-like receptors (TLR2, TLR9) on dendritic cells, promotes T-cell maturation and differentiation, enhances NK cell cytotoxicity, and modu",
            instructions: "Subcutaneous injection",
            storage: "Lyophilized: 2-8°C. Reconstituted: 2-8°C for up to 14 days.",
            stackNotes: "Ll 37, Kpv, Thymulin",
            warnings: "Injection site discomfort; Mild fatigue"
        ),
        PeptideInfo(
            name: "Thymulin", aliases: ["thymulin", "thymulin (facteur thymique serique)"],
            category: "Immune", defaultDose: "1-5 mg", timing: "AM",
            frequency: "2-3x per week", injectionSite: "Subcutaneous", cycleLength: "4-8 weeks",
            benefit: "T-cell maturation support",
            mechanism: "Binds to specific receptors on T-cell precursors promoting their differentiation into mature T-cells, modulates cytokine production, and requires zinc",
            instructions: "Subcutaneous injection",
            storage: "Lyophilized: -20°C. Reconstituted: 2-8°C for up to 7 days.",
            stackNotes: "Thymosin Alpha 1, Kpv, Ll 37",
            warnings: "Injection site reaction; Mild fatigue"
        ),
        PeptideInfo(
            name: "Lactoferrin", aliases: ["lactoferrin", "lactoferrin (iron-binding glycoprotein)"],
            category: "Immune", defaultDose: "200-600 mg", timing: "AM",
            frequency: "1-2x daily", injectionSite: "Oral", cycleLength: "4-12 weeks",
            benefit: "Broad antimicrobial activity",
            mechanism: "Sequesters iron from pathogens (bacteriostatic), directly disrupts bacterial membranes, activates NK cells and macrophages, and modulates inflammatory",
            instructions: "Oral capsule or powder",
            storage: "Room temperature, protect from moisture. Refrigerate after opening.",
            stackNotes: "Thymosin Alpha 1, Ll 37, Beta Defensin",
            warnings: "Mild GI discomfort; Constipation (iron-related)"
        ),
        PeptideInfo(
            name: "Beta-Defensin", aliases: ["beta defensin", "human beta-defensin peptides"],
            category: "Immune", defaultDose: "50-200 mcg", timing: "AM",
            frequency: "Daily or as needed", injectionSite: "Subcutaneous", cycleLength: "2-4 weeks",
            benefit: "Broad antimicrobial activity",
            mechanism: "Form pores in microbial membranes causing lysis, recruit immune cells via CCR6 receptor chemotaxis, and bridge innate and adaptive immunity by activat",
            instructions: "Topical or subcutaneous",
            storage: "Lyophilized: -20°C. Reconstituted: 2-8°C, use within 7 days.",
            stackNotes: "Ll 37, Thymosin Alpha 1, Lactoferrin",
            warnings: "Local inflammation; Injection site redness"
        ),
        PeptideInfo(
            name: "TA1", aliases: ["ta1", "thymosin alpha-1 (ta1 - clinical form)"],
            category: "Immune", defaultDose: "1.6 mg", timing: "AM",
            frequency: "2x per week", injectionSite: "Subcutaneous", cycleLength: "6-12 months (hepatitis) or 4-8 weeks (general)",
            benefit: "Standardized immune enhancement",
            mechanism: "Activates TLR2/9 on dendritic cells, promotes T-cell differentiation, and enhances cytokine-mediated immune signaling cascades.",
            instructions: "Subcutaneous injection",
            storage: "Lyophilized: 2-8°C. Reconstituted: use immediately or refrigerate up to 24 hours",
            stackNotes: "Thymosin Alpha 1, Thymulin, Lactoferrin",
            warnings: "Injection site discomfort; Mild erythema"
        ),
        PeptideInfo(
            name: "PT-141 (Bremelanotide)", aliases: ["pt 141", "bremelanotide (pt-141 / vyleesi)"],
            category: "Sexual Health", defaultDose: "1.75 mg", timing: "AM",
            frequency: "As needed, 45 min before activity", injectionSite: "Subcutaneous", cycleLength: "As needed",
            benefit: "Increased sexual desire",
            mechanism: "MC4R agonist in hypothalamus activating central sexual arousal pathways. Increases dopaminergic signaling independent of vascular mechanisms.",
            instructions: "Subcutaneous",
            storage: "Room temperature (autoinjector). Lyophilized: 2-8°C.",
            stackNotes: "Kisspeptin 10, Oxytocin",
            warnings: "Nausea (40%); Flushing"
        ),
        PeptideInfo(
            name: "Kisspeptin-10", aliases: ["kisspeptin 10", "kisspeptin-10 (metastin 45-54)"],
            category: "Sexual Health", defaultDose: "1-10 nmol/kg", timing: "AM",
            frequency: "Single dose or daily", injectionSite: "Subcutaneous", cycleLength: "Acute or short-course",
            benefit: "Stimulates GnRH naturally",
            mechanism: "Binds KISS1R on GnRH neurons, stimulating GnRH pulsatile release for LH/FSH secretion. Also enhances limbic sexual arousal circuits.",
            instructions: "IV or Subcutaneous",
            storage: "Lyophilized: -20°C. Reconstituted: use immediately.",
            stackNotes: "Pt 141, Oxytocin",
            warnings: "Hot flashes; Headache"
        ),
        PeptideInfo(
            name: "Melanotan II", aliases: ["melanotan ii", "melanotan ii (mt-ii)"],
            category: "Sexual Health", defaultDose: "0.25-1 mg", timing: "AM",
            frequency: "Every other day (loading), then as needed", injectionSite: "Subcutaneous", cycleLength: "Tanning: 2-4 weeks; Sexual: as needed",
            benefit: "Skin tanning",
            mechanism: "Non-selective MCR agonist: MC1R produces tanning, MC3R/MC4R increase sexual arousal, MC4R suppresses appetite. Broader receptor activity than PT-141.",
            instructions: "Subcutaneous",
            storage: "Lyophilized: 2-8°C. Reconstituted: 2-8°C for 30 days.",
            stackNotes: "Pt 141, Kisspeptin 10",
            warnings: "Nausea (common initially); Facial flushing"
        ),
        PeptideInfo(
            name: "Oxytocin", aliases: ["oxytocin", "oxytocin (oxt)"],
            category: "Sexual Health", defaultDose: "20-40 IU intranasal", timing: "AM",
            frequency: "As needed or daily", injectionSite: "As directed", cycleLength: "Variable",
            benefit: "Enhanced social bonding",
            mechanism: "Binds OXTR in social cognition brain regions (amygdala, nucleus accumbens) and reproductive organs. Modulates serotonin and dopamine in reward circuit",
            instructions: "Intranasal or IV (obstetric)",
            storage: "Nasal spray: room temperature. Solution: refrigerated.",
            stackNotes: "Pt 141, Kisspeptin 10",
            warnings: "Nasal irritation; Headache"
        ),
        PeptideInfo(
            name: "Tadalafil Peptide", aliases: ["tadalafil peptide", "tadalafil-peptide conjugate (experimental)"],
            category: "Sexual Health", defaultDose: "1-5 mg equivalent", timing: "AM",
            frequency: "As needed", injectionSite: "Subcutaneous", cycleLength: "As needed",
            benefit: "Targeted PDE5 inhibition",
            mechanism: "CPP moiety facilitates targeted PDE5 inhibitor delivery to penile smooth muscle. Local PDE5 inhibition increases cGMP for NO-mediated vasodilation wit",
            instructions: "Topical or local injection",
            storage: "Refrigerated 2-8°C.",
            stackNotes: "Pt 141, Kisspeptin 10",
            warnings: "Local irritation; Less systemic headache/flushing"
        ),
        PeptideInfo(
            name: "Selank", aliases: ["selank", "selank (tp-7)"],
            category: "Cognitive", defaultDose: "250-750 mcg", timing: "AM",
            frequency: "2-3x daily", injectionSite: "As directed", cycleLength: "2-4 weeks (cycle)",
            benefit: "Anxiolytic without sedation",
            mechanism: "Modulates GABA-A allosteric sites, increases BDNF, stabilizes enkephalin degradation, and influences serotonin metabolism. Enhances IL-6 and Th1/Th2 b",
            instructions: "Intranasal",
            storage: "Solution: 2-8°C. Protected from light.",
            stackNotes: "Semax, Noopept, Bpc 157",
            warnings: "Nasal irritation; Mild fatigue (initial)"
        ),
        PeptideInfo(
            name: "Semax", aliases: ["semax", "semax (acth 4-10 analog)"],
            category: "Cognitive", defaultDose: "200-600 mcg", timing: "AM",
            frequency: "2-3x daily", injectionSite: "As directed", cycleLength: "2-4 weeks",
            benefit: "Enhanced attention/focus",
            mechanism: "Activates MC3/4R, increases BDNF and NGF, modulates dopamine/serotonin, enhances neuronal survival via TrkB, and promotes CREB-mediated neuroplasticit",
            instructions: "Intranasal",
            storage: "Solution: 2-8°C. Use within 30 days of opening.",
            stackNotes: "Selank, Noopept, Bpc 157",
            warnings: "Nasal irritation; Headache"
        ),
        PeptideInfo(
            name: "Dihexa", aliases: ["dihexa", "dihexa (n-hexanoic-tyr-ile-(6)-aminohexanoic amide)"],
            category: "Cognitive", defaultDose: "10-20 mg (oral) or 2-5 mg (SubQ)", timing: "AM",
            frequency: "Daily", injectionSite: "Subcutaneous", cycleLength: "4-8 weeks",
            benefit: "Dramatic synaptogenesis",
            mechanism: "Allosteric potentiator of HGF/c-Met signaling driving synaptogenesis, dendritic spine formation, and neuronal survival in hippocampal circuits.",
            instructions: "Oral or Subcutaneous",
            storage: "Room temperature (capsule). Solution: -20°C.",
            stackNotes: "Semax, Selank, Noopept",
            warnings: "Limited safety data; Theoretical cancer concern (c-Met)"
        ),
        PeptideInfo(
            name: "NSI-189", aliases: ["nsi 189", "nsi-189 phosphate (neurogenic compound)"],
            category: "Cognitive", defaultDose: "40-80 mg", timing: "AM",
            frequency: "Once daily", injectionSite: "Oral", cycleLength: "8-12 weeks",
            benefit: "Hippocampal neurogenesis",
            mechanism: "Stimulates hippocampal neural stem cell proliferation and differentiation via Akt/CREB/BDNF signaling. Increases hippocampal volume visible on MRI.",
            instructions: "Oral",
            storage: "Room temperature, protected from moisture.",
            stackNotes: "Dihexa, Semax, Selank",
            warnings: "Headache; Insomnia"
        ),
        PeptideInfo(
            name: "Cerebrolysin", aliases: ["cerebrolysin", "cerebrolysin (brain-derived peptide preparation)"],
            category: "Cognitive", defaultDose: "5-30 mL", timing: "AM",
            frequency: "Daily for 10-20 days", injectionSite: "As directed", cycleLength: "10-20 day courses, 2-4x yearly",
            benefit: "Neurotrophic support",
            mechanism: "Contains fragments mimicking NGF, BDNF, GDNF, CNTF. Enhances synaptic plasticity, promotes neuronal sprouting, reduces amyloid-beta, and stabilizes ca",
            instructions: "Intramuscular or IV",
            storage: "Refrigerated 2-8°C. Amber ampoules.",
            stackNotes: "Semax, Selank, P21",
            warnings: "Injection pain; Dizziness"
        ),
        PeptideInfo(
            name: "P21", aliases: ["p21", "p21 (cntf-derived tetrapeptide)"],
            category: "Cognitive", defaultDose: "50-100 mcg/kg", timing: "AM",
            frequency: "Daily", injectionSite: "Subcutaneous", cycleLength: "4-8 weeks",
            benefit: "Hippocampal neurogenesis",
            mechanism: "Mimics CNTF neurogenesis-enhancing portion by increasing BDNF and activating PI3K/Akt. Inhibits LIF signaling to selectively promote neural stem cell ",
            instructions: "Intranasal or Subcutaneous",
            storage: "Lyophilized: -20°C.",
            stackNotes: "Cerebrolysin, Semax, Dihexa",
            warnings: "Limited safety data; Nasal irritation"
        ),
        PeptideInfo(
            name: "FGL", aliases: ["fgl", "fgl (ncam-derived peptide)"],
            category: "Cognitive", defaultDose: "1-5 mg/kg (research)", timing: "AM",
            frequency: "Daily or every other day", injectionSite: "Subcutaneous", cycleLength: "2-4 weeks",
            benefit: "Synaptic plasticity",
            mechanism: "Mimics NCAM FG loop interacting with FGFR1 to promote LTP, neurite outgrowth, neuronal survival, and presynaptic function enhancement.",
            instructions: "Subcutaneous",
            storage: "Lyophilized: -20°C.",
            stackNotes: "Semax, Cerebrolysin, P21",
            warnings: "Limited data; Theoretical mitogenic concern"
        ),
        PeptideInfo(
            name: "IDRA-21", aliases: ["idra 21", "idra-21 (benzothiadiazide ampa pam)"],
            category: "Cognitive", defaultDose: "10-30 mg", timing: "AM",
            frequency: "2-3x per week", injectionSite: "Oral", cycleLength: "4-8 weeks",
            benefit: "AMPA receptor potentiation",
            mechanism: "Binds AMPA receptors allosterically, reducing desensitization rates to prolong excitatory currents and facilitate LTP for memory encoding.",
            instructions: "Oral",
            storage: "Room temperature, dry, protected from light.",
            stackNotes: "Noopept, Semax, Selank",
            warnings: "Excitotoxicity risk potential; Headache"
        ),
        PeptideInfo(
            name: "Noopept", aliases: ["noopept", "noopept (gvs-111)"],
            category: "Cognitive", defaultDose: "10-30 mg", timing: "AM",
            frequency: "2-3x daily", injectionSite: "Oral", cycleLength: "4-8 weeks (cycle)",
            benefit: "Enhanced memory/learning",
            mechanism: "Metabolized to cycloprolylglycine which modulates AMPA/NMDA receptors. Increases NGF and BDNF in hippocampus/cortex. Antioxidant neuroprotection and a",
            instructions: "Oral or Sublingual",
            storage: "Room temperature, dry, sealed.",
            stackNotes: "Selank, Semax, Idra 21",
            warnings: "Headache; Irritability"
        ),
        PeptideInfo(
            name: "Gonadorelin", aliases: ["gonadorelin", "gonadorelin (gnrh analog)"],
            category: "Hormone", defaultDose: "100-500 mcg", timing: "AM",
            frequency: "2-3x per week or pulsatile", injectionSite: "Subcutaneous", cycleLength: "4-12 weeks",
            benefit: "Maintains natural hormone production",
            mechanism: "Binds GnRH receptors on pituitary gonadotrophs to stimulate LH and FSH release, maintaining testicular/ovarian function and natural sex hormone produc",
            instructions: "Subcutaneous injection",
            storage: "Lyophilized: 2-8°C. Reconstituted: 2-8°C for up to 14 days.",
            stackNotes: "Kisspeptin 10, Pt 141, Oxytocin",
            warnings: "Injection site reaction; Headache"
        ),
        PeptideInfo(
            name: "Follistatin 344", aliases: ["follistatin 344", "follistatin 344 (fst-344)"],
            category: "Muscle Growth", defaultDose: "100-200 mcg", timing: "AM",
            frequency: "Daily for 10-30 days", injectionSite: "Subcutaneous", cycleLength: "10-30 day protocols",
            benefit: "Significant muscle growth",
            mechanism: "Binds myostatin and activin A with high affinity, preventing ActRIIB receptor activation. Removes the brake on muscle growth allowing uninhibited sate",
            instructions: "Subcutaneous",
            storage: "Lyophilized: -20°C. Reconstituted: 2-8°C for 7 days.",
            stackNotes: "Ace 031, Igf 1 Lr3, Mgf",
            warnings: "Limited safety data; Theoretical reproductive effects"
        ),
        PeptideInfo(
            name: "ACE-031", aliases: ["ace 031", "ace-031 (soluble actriib-fc fusion)"],
            category: "Muscle Growth", defaultDose: "0.3-3 mg/kg", timing: "AM",
            frequency: "Every 2-4 weeks", injectionSite: "Subcutaneous", cycleLength: "12-24 weeks",
            benefit: "Multi-ligand pathway inhibition",
            mechanism: "Decoy receptor sequestering TGF-B ligands (myostatin, activin, GDF-11) in bloodstream, preventing cell-surface ActRIIB binding and removing multiple a",
            instructions: "Subcutaneous",
            storage: "Refrigerated 2-8°C. Do not freeze.",
            stackNotes: "Follistatin 344, Igf 1 Lr3",
            warnings: "Epistaxis; Gum bleeding"
        ),
        PeptideInfo(
            name: "IGF-1 LR3", aliases: ["igf 1 lr3", "insulin-like growth factor-1 long r3"],
            category: "Muscle Growth", defaultDose: "20-50 mcg", timing: "AM",
            frequency: "Daily (post-workout)", injectionSite: "Subcutaneous", cycleLength: "4-6 weeks",
            benefit: "Potent anabolic effects",
            mechanism: "Activates IGF-1R while evading IGFBP sequestration. Triggers PI3K/Akt/mTOR for protein synthesis, satellite cell proliferation, and amino acid uptake ",
            instructions: "Subcutaneous or Intramuscular",
            storage: "Lyophilized: -20°C. Reconstituted: 2-8°C for 21 days.",
            stackNotes: "Mgf, Follistatin 344, Bpc 157",
            warnings: "Hypoglycemia risk; Gut growth (prolonged)"
        ),
        PeptideInfo(
            name: "MGF (Mechano Growth Factor)", aliases: ["mgf", "mechano growth factor (igf-1ec splice variant)"],
            category: "Muscle Growth", defaultDose: "100-200 mcg PEG-MGF", timing: "AM",
            frequency: "2-3x per week", injectionSite: "As directed", cycleLength: "4-6 weeks",
            benefit: "Satellite cell activation",
            mechanism: "Unique E-domain activates quiescent satellite cells for proliferation. Distinct from IGF-1Ea which drives differentiation. PEGylated form extends shor",
            instructions: "Intramuscular (local)",
            storage: "Lyophilized: -20°C. Reconstituted: 2-8°C for 7 days.",
            stackNotes: "Igf 1 Lr3, Bpc 157, Tb 500",
            warnings: "Injection site soreness; Rapid degradation (non-PEG)"
        ),
        PeptideInfo(
            name: "Myostatin Inhibitor", aliases: ["myostatin inhibitor", "myostatin inhibitor peptides (anti-gdf-8)"],
            category: "Muscle Growth", defaultDose: "50-500 mcg", timing: "AM",
            frequency: "3-7x per week", injectionSite: "Subcutaneous", cycleLength: "4-12 weeks",
            benefit: "Muscle growth promotion",
            mechanism: "Propeptide mimics bind mature myostatin; peptide aptamers block ActRIIB; small antagonists compete for receptor. All prevent myostatin-mediated suppre",
            instructions: "Subcutaneous",
            storage: "Lyophilized: -20°C.",
            stackNotes: "Follistatin 344, Ace 031, Igf 1 Lr3",
            warnings: "Limited safety data; Tendon stress potential"
        ),
        PeptideInfo(
            name: "DSIP", aliases: ["dsip", "delta sleep-inducing peptide"],
            category: "Sleep", defaultDose: "100-300 mcg", timing: "Pre-bed",
            frequency: "Once before bed", injectionSite: "Subcutaneous", cycleLength: "2-4 weeks",
            benefit: "Promotes delta (deep) sleep",
            mechanism: "Modulates GABAergic and glutamatergic neurotransmission in sleep nuclei. Enhances delta wave NREM sleep, normalizes circadian patterns, and reduces co",
            instructions: "Subcutaneous or IV",
            storage: "Lyophilized: -20°C. Reconstituted: 2-8°C for 14 days.",
            stackNotes: "Epithalon, Ipamorelin, Sermorelin",
            warnings: "Morning grogginess (dose-dependent); Headache (rare)"
        ),
        PeptideInfo(
            name: "CPC-1598", aliases: ["cpc 1598", "cpc-1598 (gabaergic sleep peptide analog)"],
            category: "Sleep", defaultDose: "200-500 mcg", timing: "Pre-bed",
            frequency: "Once before bed", injectionSite: "Subcutaneous", cycleLength: "2-4 weeks",
            benefit: "Selective sleep neuron targeting",
            mechanism: "Selectively potentiates a3/a5-containing GABA-A subtypes in sleep-promoting VLPO neurons rather than broadly sedating. Promotes natural sleep onset wi",
            instructions: "Subcutaneous",
            storage: "Lyophilized: -20°C.",
            stackNotes: "Dsip, Epithalon",
            warnings: "Limited safety data; Mild morning drowsiness"
        ),
        PeptideInfo(
            name: "LGD-4033", aliases: ["lgd 4033", "ligandrol (lgd-4033)"],
            category: "Muscle Growth", defaultDose: "5-10 mg", timing: "AM",
            frequency: "Once daily", injectionSite: "Oral", cycleLength: "6-8 weeks",
            benefit: "Significant lean mass gains",
            mechanism: "Selectively binds androgen receptors in muscle and bone, activating anabolic gene transcription while avoiding prostate activity.",
            instructions: "Oral",
            storage: "Room temperature, protect from moisture and light.",
            stackNotes: "Yk 11, Follistatin 344, Igf 1 Lr3",
            warnings: "Testosterone suppression; Mild headache"
        ),
        PeptideInfo(
            name: "NA-Selank", aliases: ["na selank", "n-acetyl selank (acetylated selank)"],
            category: "Cognitive", defaultDose: "200-400 mcg", timing: "AM",
            frequency: "1-2x daily", injectionSite: "As directed", cycleLength: "2-4 weeks",
            benefit: "Enhanced anxiolytic effect",
            mechanism: "Same tuftsin-derived mechanism as Selank with acetyl group providing protease resistance; modulates GABA, enhances BDNF.",
            instructions: "Intranasal spray",
            storage: "Refrigerated 2-8°C.",
            stackNotes: "Selank, Semax, Noopept",
            warnings: "Nasal irritation; Mild sedation (rare)"
        ),
        PeptideInfo(
            name: "YK-11", aliases: ["yk 11", "yk-11 (myostatin inhibitor / sarm)"],
            category: "Muscle Growth", defaultDose: "5-10 mg", timing: "AM",
            frequency: "Once daily", injectionSite: "Oral", cycleLength: "6-8 weeks",
            benefit: "Dual anabolic mechanism",
            mechanism: "Partial androgen receptor agonist that induces follistatin expression, creating dual myostatin inhibition and AR activation.",
            instructions: "Oral",
            storage: "Room temperature, protect from light.",
            stackNotes: "Follistatin 344, Lgd 4033, Igf 1 Lr3",
            warnings: "Liver stress potential; Testosterone suppression"
        ),
        PeptideInfo(
            name: "Palmitoyl Pentapeptide-4", aliases: ["palmitoyl pentapeptide 4", "palmitoyl pentapeptide-4 (matrixyl original)"],
            category: "Skin & Anti-Aging", defaultDose: "2-8% in formulation", timing: "AM",
            frequency: "2x daily", injectionSite: "Topical", cycleLength: "8-16 weeks",
            benefit: "Proven collagen stimulation",
            mechanism: "Mimics collagen breakdown products (matrikines) that signal fibroblasts to produce new collagen matrix components including types I, III, and IV colla",
            instructions: "Topical serum or cream",
            storage: "Room temperature, protect from direct sunlight.",
            stackNotes: "Matrixyl, Ghk Cu, Collagen Peptides",
            warnings: "Mild tingling; Rare sensitivity reaction"
        ),
        PeptideInfo(
            name: "BPC-157 (Oral)", aliases: ["bpc 157 oral", "bpc-157 oral formulation (arginate salt)"],
            category: "Healing", defaultDose: "500 mcg - 1 mg", timing: "AM",
            frequency: "1-2x daily", injectionSite: "Oral", cycleLength: "4-12 weeks",
            benefit: "Gut healing (direct contact)",
            mechanism: "Same mechanism as injectable BPC-157 but delivered orally. Upregulates VEGF, modulates NO system, and promotes gut mucosal healing through direct cont",
            instructions: "Oral capsule (arginate salt)",
            storage: "Room temperature, sealed container. Protect from moisture.",
            stackNotes: "Bpc 157, Kpv, Ll 37",
            warnings: "Mild nausea; GI discomfort initially"
        ),
        PeptideInfo(
            name: "Thymalin", aliases: ["thymalin", "thymalin (thymus extract peptide)"],
            category: "Immune", defaultDose: "5-10 mg", timing: "AM",
            frequency: "Daily for 5-10 days", injectionSite: "Subcutaneous", cycleLength: "5-10 day cycles, 1-3x/year",
            benefit: "Immune reconstitution",
            mechanism: "Contains bioactive thymic peptides that regulate T-lymphocyte differentiation, restore T-helper/T-suppressor ratios, and enhance phagocyte activity an",
            instructions: "Intramuscular injection",
            storage: "Lyophilized: 2-8°C. Reconstituted: use immediately.",
            stackNotes: "Thymosin Alpha 1, Thymulin, Epithalon",
            warnings: "Injection site pain; Mild allergic reaction (rare)"
        ),
        PeptideInfo(
            name: "PEG-MGF", aliases: ["pegylated mgf", "pegylated mechano growth factor"],
            category: "Muscle Growth", defaultDose: "100-200 mcg", timing: "AM",
            frequency: "2-3x per week", injectionSite: "Subcutaneous", cycleLength: "4-6 weeks",
            benefit: "Extended half-life vs native MGF",
            mechanism: "PEGylation protects MGF from rapid degradation, extending half-life from minutes to hours. Activates satellite cells systemically for whole-body muscl",
            instructions: "Subcutaneous injection",
            storage: "Lyophilized: -20°C. Reconstituted: 2-8°C for up to 48 hours.",
            stackNotes: "Mgf, Igf 1 Lr3, Follistatin 344",
            warnings: "Injection site reaction; Mild joint ache"
        ),
        PeptideInfo(
            name: "SNAP-25 Fragment", aliases: ["snap 25 fragment", "snap-25 inhibitory fragment peptide"],
            category: "Skin & Anti-Aging", defaultDose: "3-8% in formulation", timing: "AM",
            frequency: "2x daily", injectionSite: "Topical", cycleLength: "4-8 weeks",
            benefit: "Highly specific SNARE targeting",
            mechanism: "Directly competes with the SNAP-25 binding domain in SNARE complex formation, providing highly specific inhibition of vesicle fusion at facial neuromu",
            instructions: "Topical serum",
            storage: "Room temperature, protect from heat.",
            stackNotes: "Argireline, Snap 8, Leuphasyl",
            warnings: "Mild tingling; Rare irritation"
        ),
        PeptideInfo(
            name: "Cortagen", aliases: ["cortagen", "cortagen (brain cortex peptide)"],
            category: "Cognitive", defaultDose: "10 mg", timing: "AM",
            frequency: "Daily for 10-15 days", injectionSite: "Subcutaneous", cycleLength: "10-15 day cycles, 2-3x/year",
            benefit: "Cerebral cortex optimization",
            mechanism: "Regulates gene expression in cerebral cortex neurons, modulating neurotransmitter receptor density, synaptic plasticity, and neuronal energy metabolis",
            instructions: "Oral capsule or subcutaneous injection",
            storage: "Room temperature, sealed container.",
            stackNotes: "Semax, Cerebrolysin, Noopept",
            warnings: "Mild headache initially; Drowsiness (rare)"
        ),
        PeptideInfo(
            name: "Enclomiphene", aliases: ["enclomiphene", "enclomiphene citrate"],
            category: "Hormone", defaultDose: "12.5-25 mg", timing: "AM",
            frequency: "Daily", injectionSite: "Oral", cycleLength: "Ongoing or cycled 8-12 weeks",
            benefit: "Increased endogenous testosterone",
            mechanism: "Blocks estrogen receptors in the hypothalamus, reducing negative feedback and increasing GnRH pulsatility, which stimulates LH and FSH release for end",
            instructions: "Oral capsule",
            storage: "Room temperature, protect from moisture.",
            stackNotes: "Kisspeptin 10, Gonadorelin, Dhea",
            warnings: "Headache; Mood changes"
        ),
        PeptideInfo(
            name: "Glutathione", aliases: ["glutathione", "l-glutathione (reduced)"],
            category: "Anti-Aging", defaultDose: "200-600 mg", timing: "AM",
            frequency: "1-3x per week", injectionSite: "Subcutaneous", cycleLength: "Ongoing",
            benefit: "Powerful antioxidant protection",
            mechanism: "Directly neutralizes free radicals, regenerates vitamins C and E, supports phase II liver detoxification, maintains cellular redox balance, and protec",
            instructions: "IV push, IM injection, or nebulized",
            storage: "Reconstituted: 2-8°C. Use within 30 days.",
            stackNotes: "Nad Plus, Vitamin C, Alpha Lipoic Acid",
            warnings: "Injection site pain; Mild cramping"
        ),
        PeptideInfo(
            name: "DHEA", aliases: ["dhea", "dehydroepiandrosterone"],
            category: "Hormone", defaultDose: "25-100 mg", timing: "AM",
            frequency: "Daily (morning)", injectionSite: "Topical", cycleLength: "Ongoing with monitoring",
            benefit: "Hormone precursor support",
            mechanism: "Serves as a precursor to both testosterone and estrogen. Also acts directly on DHEA-specific receptors, supports immune function, neurosteroid activit",
            instructions: "Oral capsule or topical cream",
            storage: "Room temperature.",
            stackNotes: "Pregnenolone, Enclomiphene, Vitamin D",
            warnings: "Acne; Hair loss (androgenic)"
        ),
        PeptideInfo(
            name: "Pregnenolone", aliases: ["pregnenolone", "pregnenolone (mother hormone)"],
            category: "Hormone", defaultDose: "50-100 mg", timing: "AM",
            frequency: "Daily (morning)", injectionSite: "Oral", cycleLength: "Ongoing with monitoring",
            benefit: "Hormone precursor balance",
            mechanism: "Acts as the primary substrate for steroidogenesis (cortisol, DHEA, progesterone, testosterone, estrogen). Also functions as a neurosteroid, enhancing ",
            instructions: "Oral capsule or sublingual",
            storage: "Room temperature.",
            stackNotes: "Dhea, Nad Plus, Semax",
            warnings: "Headache; Irritability"
        ),
        PeptideInfo(
            name: "Synapsin", aliases: ["synapsin", "synapsin nasal spray (rg3 + nad+ + methylcobalamin)"],
            category: "Cognitive", defaultDose: "1-2 sprays per nostril", timing: "AM",
            frequency: "1-2x daily", injectionSite: "As directed", cycleLength: "Ongoing or cycled",
            benefit: "Improved mental clarity",
            mechanism: "Rg3 reduces neuroinflammation and protects neurons. NAD+ supports mitochondrial function and sirtuin activation in brain cells. Methylcobalamin provid",
            instructions: "Intranasal spray",
            storage: "Refrigerate 2-8°C.",
            stackNotes: "Semax, Selank, Nad Plus",
            warnings: "Nasal irritation; Mild headache initially"
        ),
        PeptideInfo(
            name: "TriMix", aliases: ["trimix", "trimix (papaverine + phentolamine + alprostadil)"],
            category: "Sexual Health", defaultDose: "0.1-0.5 mL (titrated)", timing: "AM",
            frequency: "As needed, max 3x/week", injectionSite: "Subcutaneous", cycleLength: "Ongoing",
            benefit: "Reliable erectile response",
            mechanism: "Papaverine relaxes smooth muscle via PDE inhibition. Phentolamine blocks alpha-adrenergic receptors. Alprostadil (PGE1) directly stimulates cAMP produ",
            instructions: "Intracavernosal injection",
            storage: "Refrigerate 2-8°C. Protect from light.",
            stackNotes: "Pt 141, Kisspeptin 10, Oxytocin",
            warnings: "Injection pain; Priapism risk (rare)"
        ),
        PeptideInfo(
            name: "Methylene Blue", aliases: ["methylene blue", "methylene blue (methylthioninium chloride)"],
            category: "Cognitive", defaultDose: "0.5-2 mg/kg", timing: "AM",
            frequency: "Daily or cycled", injectionSite: "Oral", cycleLength: "Cycled: 2 weeks on, 1 week off",
            benefit: "Mitochondrial energy boost",
            mechanism: "Acts as an alternative electron carrier in the mitochondrial electron transport chain, bypassing complex I-III blockades. Inhibits monoamine oxidase, ",
            instructions: "Oral solution or sublingual",
            storage: "Room temperature, protect from light.",
            stackNotes: "Nad Plus, Ss 31, Semax",
            warnings: "Blue/green urine discoloration; Blue-tinged skin at high doses"
        ),
        PeptideInfo(
            name: "Biotin Injection", aliases: ["biotin injection", "biotin (vitamin b7) injectable"],
            category: "Skin & Anti-Aging", defaultDose: "1-10 mg IM", timing: "AM",
            frequency: "1-2x per week", injectionSite: "Subcutaneous", cycleLength: "12-24 weeks",
            benefit: "Hair growth support",
            mechanism: "Essential cofactor for carboxylase enzymes involved in keratin production, fatty acid synthesis, and amino acid metabolism critical for hair follicle ",
            instructions: "Intramuscular injection",
            storage: "Room temperature, protect from light.",
            stackNotes: "Ghk Cu, Collagen Peptides, Glutathione",
            warnings: "Injection site soreness; Acne (rare)"
        ),
        PeptideInfo(
            name: "Lipo-C Injection", aliases: ["lipo c injection", "lipotropic mic + b12 injection"],
            category: "Weight Management", defaultDose: "1 mL", timing: "AM",
            frequency: "1-2x per week", injectionSite: "Subcutaneous", cycleLength: "Ongoing",
            benefit: "Enhanced fat metabolism",
            mechanism: "Methionine provides sulfur for detoxification, inositol supports fat transport from liver, choline emulsifies cholesterol and fat, B12 boosts cellular",
            instructions: "Intramuscular or subcutaneous injection",
            storage: "Refrigerate 2-8°C.",
            stackNotes: "Semaglutide, Tirzepatide, 5 Amino 1Mq",
            warnings: "Injection site pain; Mild nausea"
        ),
        PeptideInfo(
            name: "L-Carnitine", aliases: ["l carnitine", "l-carnitine injectable"],
            category: "Weight Management", defaultDose: "500-2000 mg", timing: "AM",
            frequency: "2-5x per week", injectionSite: "Subcutaneous", cycleLength: "Ongoing",
            benefit: "Enhanced fat oxidation",
            mechanism: "Transports long-chain fatty acids across the inner mitochondrial membrane via the carnitine shuttle, enabling beta-oxidation for ATP production. Also ",
            instructions: "Intramuscular or IV injection",
            storage: "Room temperature or refrigerated.",
            stackNotes: "Lipo C Injection, Semaglutide, Mots C",
            warnings: "Injection site pain; Fishy body odor (high doses)"
        ),
        PeptideInfo(
            name: "Vitamin D3 Injection", aliases: ["vitamin d injection", "cholecalciferol (vitamin d3) injectable"],
            category: "Immune", defaultDose: "50,000-100,000 IU", timing: "AM",
            frequency: "Weekly to monthly", injectionSite: "Subcutaneous", cycleLength: "Until optimal levels achieved",
            benefit: "Rapid deficiency correction",
            mechanism: "Converts to 25-hydroxyvitamin D then to active 1,25-dihydroxyvitamin D. Modulates over 200 genes including those for immune function, calcium absorpti",
            instructions: "Intramuscular injection",
            storage: "Room temperature, protect from light.",
            stackNotes: "Thymosin Alpha 1, Glutathione, Zinc",
            warnings: "Injection site pain; Hypercalcemia (overdose)"
        ),
        PeptideInfo(
            name: "B12 Injection", aliases: ["b12 injection", "methylcobalamin (vitamin b12) injectable"],
            category: "Cognitive", defaultDose: "1000-5000 mcg", timing: "AM",
            frequency: "1-3x per week", injectionSite: "Subcutaneous", cycleLength: "Ongoing",
            benefit: "Increased energy",
            mechanism: "Cofactor for methionine synthase (DNA methylation) and methylmalonyl-CoA mutase (energy metabolism). Supports myelin synthesis, neurotransmitter produ",
            instructions: "Intramuscular or subcutaneous injection",
            storage: "Refrigerate 2-8°C. Protect from light.",
            stackNotes: "Synapsin, Nad Plus, Glutathione",
            warnings: "Injection site soreness; Mild diarrhea"
        ),
        PeptideInfo(
            name: "Liothyronine (T3)", aliases: ["thyroid support t3", "liothyronine sodium (cytomel)"],
            category: "Hormone", defaultDose: "5-25 mcg", timing: "AM",
            frequency: "Daily (split AM/PM)", injectionSite: "Oral", cycleLength: "Ongoing with monitoring",
            benefit: "Metabolic rate increase",
            mechanism: "Binds nuclear thyroid receptors to regulate gene transcription for basal metabolic rate, thermogenesis, protein synthesis, and carbohydrate/fat metabo",
            instructions: "Oral tablet or sustained-release capsule",
            storage: "Room temperature.",
            stackNotes: "Semaglutide, Mots C, L Carnitine",
            warnings: "Heart palpitations; Anxiety"
        ),
        PeptideInfo(
            name: "Low-Dose Naltrexone (LDN)", aliases: ["naltrexone low dose", "low-dose naltrexone"],
            category: "Pain", defaultDose: "1.5-4.5 mg", timing: "AM",
            frequency: "Nightly at bedtime", injectionSite: "Oral", cycleLength: "Ongoing",
            benefit: "Immune modulation",
            mechanism: "Brief nocturnal opioid receptor blockade triggers compensatory upregulation of endogenous opioid production and OGF (opioid growth factor), modulating",
            instructions: "Oral capsule (compounded)",
            storage: "Room temperature.",
            stackNotes: "Bpc 157, Kpv, Thymosin Alpha 1",
            warnings: "Vivid dreams; Initial sleep disruption"
        ),
        PeptideInfo(
            name: "Amlexanox", aliases: ["peptide amlexanox", "amlexanox (tbk1/ikkε inhibitor)"],
            category: "Weight Management", defaultDose: "25-100 mg", timing: "AM",
            frequency: "3x daily", injectionSite: "Oral", cycleLength: "8-12 weeks",
            benefit: "Increased energy expenditure",
            mechanism: "Inhibits IKKε and TBK1 kinases that are upregulated in obesity, which normally suppress energy expenditure. Blocking these kinases restores thermogene",
            instructions: "Oral tablet",
            storage: "Room temperature.",
            stackNotes: "Semaglutide, 5 Amino 1Mq, Mots C",
            warnings: "GI upset; Diarrhea"
        ),
        PeptideInfo(
            name: "Rapamycin", aliases: ["rapamycin", "rapamycin (sirolimus)"],
            category: "Anti-Aging", defaultDose: "3-6 mg", timing: "AM",
            frequency: "Once weekly", injectionSite: "Oral", cycleLength: "Ongoing (pulsed)",
            benefit: "Enhanced autophagy",
            mechanism: "Inhibits mTOR complex 1 (mTORC1), reducing cellular growth signaling and activating autophagy — the cellular recycling process. Mimics caloric restric",
            instructions: "Oral tablet",
            storage: "Room temperature.",
            stackNotes: "Nad Plus, Epithalon, Ss 31",
            warnings: "Mouth sores; Impaired wound healing"
        ),
        PeptideInfo(
            name: "Metformin", aliases: ["metformin", "metformin hydrochloride"],
            category: "Anti-Aging", defaultDose: "500-1000 mg", timing: "AM",
            frequency: "1-2x daily", injectionSite: "Oral", cycleLength: "Ongoing",
            benefit: "AMPK activation",
            mechanism: "Activates AMP-activated protein kinase (AMPK), inhibits mitochondrial complex I, reduces hepatic glucose output, and activates autophagy. Mimics the m",
            instructions: "Oral tablet (extended-release preferred)",
            storage: "Room temperature.",
            stackNotes: "Rapamycin, Nad Plus, Mots C",
            warnings: "GI upset; Diarrhea"
        ),
        PeptideInfo(
            name: "Alpha-Lipoic Acid (ALA)", aliases: ["alpha lipoic acid", "r-alpha-lipoic acid injectable"],
            category: "Anti-Aging", defaultDose: "200-600 mg", timing: "AM",
            frequency: "1-3x per week (injectable)", injectionSite: "Subcutaneous", cycleLength: "Ongoing or cycled",
            benefit: "Universal antioxidant",
            mechanism: "Regenerates glutathione, vitamin C, and vitamin E. Chelates heavy metals. Acts as cofactor for mitochondrial enzyme complexes. Activates Nrf2 pathway ",
            instructions: "IV/IM injection or oral capsule",
            storage: "Protect from light and heat.",
            stackNotes: "Glutathione, Nad Plus, B12 Injection",
            warnings: "Mild nausea; Skin rash (rare)"
        ),
        PeptideInfo(
            name: "Tadalafil", aliases: ["tadalafil", "tadalafil (cialis)"],
            category: "Sexual Health", defaultDose: "2.5-5 mg daily or 10-20 mg as needed", timing: "AM",
            frequency: "Daily or on-demand", injectionSite: "Oral", cycleLength: "Ongoing",
            benefit: "Erectile function improvement",
            mechanism: "Selectively inhibits phosphodiesterase type 5 (PDE5), preventing cGMP breakdown in smooth muscle. This enhances nitric oxide signaling for vasodilatio",
            instructions: "Oral tablet",
            storage: "Room temperature.",
            stackNotes: "Pt 141, Kisspeptin 10, L Carnitine",
            warnings: "Headache; Back pain"
        ),
        PeptideInfo(
            name: "Compounded Semaglutide", aliases: ["ozempic compound", "compounded semaglutide (503b pharmacy)"],
            category: "Weight Management", defaultDose: "0.25-2.4 mg", timing: "AM",
            frequency: "Once weekly", injectionSite: "Subcutaneous", cycleLength: "12-52+ weeks",
            benefit: "Significant weight loss (15-20%)",
            mechanism: "Identical to branded semaglutide — a GLP-1 receptor agonist with a fatty acid chain for albumin binding, providing extended half-life. Reduces appetit",
            instructions: "Subcutaneous injection",
            storage: "Refrigerate 2-8°C before first use. Room temp up to 30 days after.",
            stackNotes: "Lipo C Injection, L Carnitine, 5 Amino 1Mq",
            warnings: "Nausea; Vomiting"
        ),
        PeptideInfo(
            name: "Compounded Tirzepatide", aliases: ["tirzepatide compound", "compounded tirzepatide (503b pharmacy)"],
            category: "Weight Management", defaultDose: "2.5-15 mg", timing: "AM",
            frequency: "Once weekly", injectionSite: "Subcutaneous", cycleLength: "12-52+ weeks",
            benefit: "Superior weight loss (20-25%)",
            mechanism: "Dual agonist of both GLP-1 and GIP receptors. GLP-1 activation suppresses appetite and slows gastric emptying. GIP activation enhances fat metabolism,",
            instructions: "Subcutaneous injection",
            storage: "Refrigerate 2-8°C.",
            stackNotes: "Lipo C Injection, L Carnitine, Mots C",
            warnings: "Nausea; Diarrhea"
        ),
        PeptideInfo(
            name: "Dihexa (Oral)", aliases: ["dihexa oral", "dihexa (n-hexanoic-tyr-ile-(6) aminohexanoic amide)"],
            category: "Cognitive", defaultDose: "10-20 mg", timing: "AM",
            frequency: "Daily or every other day", injectionSite: "Oral", cycleLength: "4-8 weeks cycled",
            benefit: "Synaptogenesis (new brain connections)",
            mechanism: "Activates hepatocyte growth factor (HGF) / c-Met receptor system in the brain, triggering dendritic spine formation, synaptogenesis, and neuronal surv",
            instructions: "Oral capsule or sublingual",
            storage: "Room temperature, dry and sealed.",
            stackNotes: "Semax, Cerebrolysin, Noopept",
            warnings: "Headache; Overstimulation"
        ),
        PeptideInfo(
            name: "Ibutamoren (MK-677) Oral", aliases: ["ibutamoren oral", "ibutamoren mesylate (mk-677)"],
            category: "GH Secretagogue", defaultDose: "10-25 mg", timing: "AM",
            frequency: "Once daily (evening)", injectionSite: "Oral", cycleLength: "12-24 weeks or longer",
            benefit: "Elevated IGF-1 levels",
            mechanism: "Mimics ghrelin at the GHS-R1a receptor in the pituitary and hypothalamus, stimulating sustained GH release without suppressing natural pulsatility. Al",
            instructions: "Oral capsule or liquid",
            storage: "Room temperature.",
            stackNotes: "Cjc 1295, Ipamorelin, Sermorelin",
            warnings: "Increased hunger; Water retention"
        ),
        PeptideInfo(
            name: "Anastrozole", aliases: ["anastrozole", "anastrozole (arimidex)"],
            category: "Hormone", defaultDose: "0.25-0.5 mg", timing: "AM",
            frequency: "2-3x per week", injectionSite: "Oral", cycleLength: "As long as on TRT/hormone therapy",
            benefit: "Estrogen control",
            mechanism: "Selectively and reversibly inhibits aromatase (CYP19A1), the enzyme that converts androgens to estrogens. Reduces circulating estradiol levels without",
            instructions: "Oral tablet",
            storage: "Room temperature.",
            stackNotes: "Enclomiphene, Gonadorelin, Dhea",
            warnings: "Joint pain/stiffness; Bone density loss (long-term)"
        ),
        PeptideInfo(
            name: "Zinc Injection", aliases: ["zinc injectable", "zinc sulfate injectable"],
            category: "Immune", defaultDose: "5-10 mg elemental zinc", timing: "AM",
            frequency: "1-2x per week", injectionSite: "Subcutaneous", cycleLength: "Until optimal levels",
            benefit: "Immune system support",
            mechanism: "Essential cofactor for 300+ enzymes. Critical for T-cell maturation, NK cell activity, zinc finger protein transcription factors, testosterone synthes",
            instructions: "Intramuscular or IV injection",
            storage: "Room temperature.",
            stackNotes: "Thymosin Alpha 1, Vitamin D Injection, Glutathione",
            warnings: "Injection site pain; Nausea"
        ),
        PeptideInfo(
            name: "Testosterone Cypionate", aliases: ["testosterone cypionate", "testosterone cypionate (depo-testosterone)"],
            category: "Hormone", defaultDose: "100-200 mg", timing: "AM",
            frequency: "Weekly or split biweekly", injectionSite: "Subcutaneous", cycleLength: "Ongoing (lifetime TRT)",
            benefit: "Restored libido and sexual function",
            mechanism: "Exogenous testosterone binds androgen receptors in muscle, bone, brain, and reproductive tissues. The cypionate ester provides slow release from the i",
            instructions: "Intramuscular or subcutaneous injection",
            storage: "Room temperature. Protect from light. Multi-use vial stable for 28 days.",
            stackNotes: "Hcg, Anastrozole, Dhea",
            warnings: "Erythrocytosis (elevated hematocrit); Acne"
        ),
        PeptideInfo(
            name: "HCG", aliases: ["hcg", "human chorionic gonadotropin"],
            category: "Hormone", defaultDose: "500-1000 IU", timing: "AM",
            frequency: "2-3x per week", injectionSite: "Subcutaneous", cycleLength: "Ongoing with TRT",
            benefit: "Preserved testicular size",
            mechanism: "Binds LH/CG receptors on Leydig cells, stimulating intratesticular testosterone synthesis and maintaining spermatogenesis via local paracrine signalin",
            instructions: "Subcutaneous injection",
            storage: "Lyophilized: 2-8°C. Reconstituted: refrigerate, use within 30 days.",
            stackNotes: "Testosterone Cypionate, Anastrozole, Gonadorelin",
            warnings: "Estradiol elevation; Water retention"
        ),
        PeptideInfo(
            name: "Progesterone", aliases: ["progesterone", "micronized progesterone (prometrium)"],
            category: "Hormone", defaultDose: "100-200 mg oral or 20-40 mg topical", timing: "AM",
            frequency: "Nightly (oral) or daily (topical)", injectionSite: "Topical", cycleLength: "Ongoing",
            benefit: "Enhanced deep sleep (GABA modulation)",
            mechanism: "Agonizes progesterone receptors and GABA-A receptors (via allopregnanolone metabolite). Inhibits 5-alpha reductase, opposes estrogen proliferative eff",
            instructions: "Oral capsule, topical cream, or vaginal",
            storage: "Room temperature. Protect from light and moisture.",
            stackNotes: "Testosterone Cypionate, Dhea, Pregnenolone",
            warnings: "Drowsiness; Mild dizziness"
        ),
        PeptideInfo(
            name: "Kisspeptin-10", aliases: ["kisspeptin 10", "kisspeptin-10 (metastin 45-54)"],
            category: "Hormone", defaultDose: "100-400 mcg", timing: "AM",
            frequency: "1-2x daily", injectionSite: "Subcutaneous", cycleLength: "4-12 weeks",
            benefit: "Natural testosterone restoration",
            mechanism: "Binds KISS1R (GPR54) receptors on GnRH neurons in the hypothalamus, triggering pulsatile GnRH release. This cascades to LH/FSH secretion from the pitu",
            instructions: "Subcutaneous injection",
            storage: "Lyophilized: -20°C. Reconstituted: 2-8°C for up to 14 days.",
            stackNotes: "Gonadorelin, Enclomiphene, Hcg",
            warnings: "Flushing; Mild headache"
        ),
        PeptideInfo(
            name: "Clomiphene Citrate", aliases: ["clomiphene citrate", "clomiphene citrate (clomid)"],
            category: "Hormone", defaultDose: "12.5-50 mg", timing: "AM",
            frequency: "Daily or every other day", injectionSite: "Oral", cycleLength: "3-6 months",
            benefit: "Increased endogenous testosterone",
            mechanism: "Blocks estrogen receptors in the hypothalamus, preventing negative feedback. This increases GnRH pulsatility, elevating pituitary LH and FSH output an",
            instructions: "Oral",
            storage: "Room temperature. Protect from light and moisture.",
            stackNotes: "Anastrozole, Dhea, Gonadorelin",
            warnings: "Visual disturbances (rare); Mood swings"
        ),
        PeptideInfo(
            name: "Oxandrolone", aliases: ["oxandrolone", "oxandrolone (anavar)"],
            category: "Hormone", defaultDose: "10-20 mg (therapeutic); 20-50 mg (performance)", timing: "AM",
            frequency: "Split 2x daily", injectionSite: "Oral", cycleLength: "6-8 weeks",
            benefit: "Lean muscle gain without water retention",
            mechanism: "Binds androgen receptors with high anabolic:androgenic ratio (~10:1). Does not aromatize to estrogen. Increases nitrogen retention, protein synthesis,",
            instructions: "Oral",
            storage: "Room temperature. Protect from moisture.",
            stackNotes: "Testosterone Cypionate, Hcg, L Carnitine",
            warnings: "Lipid disruption (HDL decrease); Mild liver stress"
        ),
        PeptideInfo(
            name: "Larazotide", aliases: ["larazotide", "larazotide acetate (at-1001)"],
            category: "Gut Health", defaultDose: "0.5-1 mg", timing: "AM",
            frequency: "3x daily before meals", injectionSite: "Oral", cycleLength: "12-16 weeks",
            benefit: "Reduced intestinal permeability",
            mechanism: "Acts as a zonulin peptide antagonist, preventing zonulin-mediated disassembly of tight junction proteins (ZO-1, occludin, claudins). Maintains paracel",
            instructions: "Oral capsule",
            storage: "Room temperature. Protect from moisture.",
            stackNotes: "Bpc 157 Oral, Butyrate, Colostrum",
            warnings: "Headache (mild); Nausea (rare)"
        ),
        PeptideInfo(
            name: "Colostrum", aliases: ["colostrum", "bovine colostrum (igg-rich)"],
            category: "Gut Health", defaultDose: "5-20 g powder or 500-2000 mg capsules", timing: "AM",
            frequency: "Daily on empty stomach", injectionSite: "Oral", cycleLength: "Ongoing or 8-12 week cycles",
            benefit: "Gut barrier repair",
            mechanism: "IgG antibodies bind gut pathogens and endotoxins. Growth factors (EGF, TGF-β) stimulate epithelial cell proliferation and repair. Proline-rich polypep",
            instructions: "Oral (powder or capsule)",
            storage: "Room temperature (powder). Refrigerate after opening.",
            stackNotes: "Bpc 157 Oral, Lactoferrin, Butyrate",
            warnings: "Mild bloating initially; Dairy sensitivity (contains lactose)"
        ),
        PeptideInfo(
            name: "BPC-157 Oral", aliases: ["bpc 157 oral", "bpc-157 oral (stable arginine salt)"],
            category: "Gut Health", defaultDose: "250-500 mcg", timing: "AM",
            frequency: "2x daily on empty stomach", injectionSite: "Oral", cycleLength: "4-8 weeks",
            benefit: "Gastric ulcer healing",
            mechanism: "Upregulates VEGF and EGF receptors in GI mucosa, promotes angiogenesis at ulcer/lesion sites, modulates nitric oxide system, and interacts with dopami",
            instructions: "Oral capsule or sublingual",
            storage: "Room temperature in sealed capsules. Protect from moisture.",
            stackNotes: "Larazotide, Colostrum, Butyrate",
            warnings: "Mild nausea (initial); Temporary changes in bowel habits"
        ),
        PeptideInfo(
            name: "Butyrate", aliases: ["butyrate", "sodium butyrate / tributyrin"],
            category: "Gut Health", defaultDose: "300-600 mg tributyrin or 500-2000 mg sodium butyrate", timing: "AM",
            frequency: "2-3x daily with meals", injectionSite: "Oral", cycleLength: "Ongoing",
            benefit: "Colonocyte energy support",
            mechanism: "Inhibits histone deacetylases (HDACs) for anti-inflammatory gene expression. Fuels colonocyte mitochondria via beta-oxidation. Strengthens tight junct",
            instructions: "Oral (enteric-coated or tributyrin pro-drug)",
            storage: "Room temperature. Sealed container (pungent odor if exposed).",
            stackNotes: "Colostrum, Bpc 157 Oral, Larazotide",
            warnings: "GI gas/bloating; Unpleasant taste/odor (sodium butyrate)"
        ),
        PeptideInfo(
            name: "Akkermansia", aliases: ["akkermansia", "akkermansia muciniphila (pasteurized)"],
            category: "Gut Health", defaultDose: "10 billion CFU (pasteurized) or 100mg membrane extract", timing: "AM",
            frequency: "Daily", injectionSite: "Oral", cycleLength: "Ongoing (8-12 weeks minimum for metabolic effects)",
            benefit: "Improved metabolic markers",
            mechanism: "Amuc_1100 outer membrane protein activates TLR2 signaling, strengthening gut barrier and improving metabolic endotoxemia. Stimulates mucin production ",
            instructions: "Oral capsule",
            storage: "Room temperature (pasteurized). Live form: refrigerate.",
            stackNotes: "Butyrate, Colostrum, Metformin",
            warnings: "Mild GI adjustment period; Temporary bloating"
        ),
        PeptideInfo(
            name: "Nattokinase", aliases: ["nattokinase", "nattokinase (subtilisin nat)"],
            category: "Cardiovascular", defaultDose: "2000-4000 FU (fibrinolytic units)", timing: "AM",
            frequency: "Daily on empty stomach", injectionSite: "Oral", cycleLength: "Ongoing",
            benefit: "Fibrin clot dissolution",
            mechanism: "Directly degrades fibrin in blood clots via proteolytic activity. Also activates endogenous tissue plasminogen activator (tPA) and suppresses plasmino",
            instructions: "Oral capsule",
            storage: "Room temperature. Protect from moisture and heat.",
            stackNotes: "Omega 3, Coq10, Serrapeptase",
            warnings: "Increased bleeding risk; Bruising"
        ),
        PeptideInfo(
            name: "Serrapeptase", aliases: ["serrapeptase", "serrapeptase (serratiopeptidase)"],
            category: "Cardiovascular", defaultDose: "120,000-240,000 SPU", timing: "AM",
            frequency: "Daily on empty stomach", injectionSite: "Oral", cycleLength: "Ongoing or 8-12 week cycles",
            benefit: "Reduced inflammation and swelling",
            mechanism: "Degrades non-living tissue including fibrin, blood clots, mucus, and arterial plaque without harming living cells. Inhibits bradykinin release and red",
            instructions: "Oral (enteric-coated)",
            storage: "Room temperature. Keep dry.",
            stackNotes: "Nattokinase, Omega 3, Coq10",
            warnings: "Nausea (if taken with food); Rare: skin rash"
        ),
        PeptideInfo(
            name: "CoQ10", aliases: ["coq10", "coenzyme q10 (ubiquinol)"],
            category: "Cardiovascular", defaultDose: "100-300 mg ubiquinol", timing: "AM",
            frequency: "Daily with fat-containing meal", injectionSite: "Oral", cycleLength: "Ongoing",
            benefit: "Mitochondrial energy production",
            mechanism: "Shuttles electrons in the mitochondrial respiratory chain (Complex I→III). As ubiquinol, neutralizes lipid peroxyl radicals protecting cell membranes ",
            instructions: "Oral softgel",
            storage: "Room temperature. Protect from light and heat.",
            stackNotes: "Pqq, Omega 3, Nad Plus",
            warnings: "Rare: mild GI upset; Insomnia (if taken late)"
        ),
        PeptideInfo(
            name: "Omega-3 (EPA/DHA)", aliases: ["omega 3", "omega-3 fatty acids (epa + dha)"],
            category: "Cardiovascular", defaultDose: "2-4g combined EPA+DHA", timing: "AM",
            frequency: "Daily with meals", injectionSite: "Oral", cycleLength: "Ongoing",
            benefit: "Triglyceride reduction (25-45%)",
            mechanism: "EPA/DHA incorporate into cell membranes, displacing arachidonic acid and reducing pro-inflammatory eicosanoid production. Generate resolvins and prote",
            instructions: "Oral (softgel, liquid)",
            storage: "Refrigerate after opening. Protect from light and oxidation.",
            stackNotes: "Nattokinase, Coq10, Vitamin D Injection",
            warnings: "Fishy aftertaste/burping; Mild GI discomfort"
        ),
        PeptideInfo(
            name: "Bergamot Extract", aliases: ["bergamot", "citrus bergamia polyphenol extract"],
            category: "Cardiovascular", defaultDose: "500-1000 mg standardized extract", timing: "AM",
            frequency: "Daily with meals", injectionSite: "Oral", cycleLength: "Ongoing (8-12 weeks for lipid effects)",
            benefit: "LDL cholesterol reduction (20-35%)",
            mechanism: "Polyphenolic flavonoids (brutieridin, melitidin) inhibit HMG-CoA reductase (same target as statins). Activates AMPK for fat oxidation. Reduces PCSK9 e",
            instructions: "Oral capsule",
            storage: "Room temperature. Protect from light.",
            stackNotes: "Omega 3, Coq10, Metformin",
            warnings: "Mild GI discomfort (rare); Potential drug interactions (CYP3A4)"
        ),
        PeptideInfo(
            name: "Glutathione (IV/IM)", aliases: ["glutathione iv", "l-glutathione (reduced, injectable)"],
            category: "Detox", defaultDose: "600-2000 mg IV push or 200-600 mg IM", timing: "AM",
            frequency: "1-3x weekly", injectionSite: "Subcutaneous", cycleLength: "8-12 week cycles",
            benefit: "Heavy metal detoxification",
            mechanism: "Directly conjugates with toxins, heavy metals, and reactive oxygen species via glutathione S-transferases. Regenerates vitamins C and E. Maintains thi",
            instructions: "Intravenous push or intramuscular injection",
            storage: "Refrigerate (2-8°C). Protect from light. Use within 24h once drawn.",
            stackNotes: "Nac, Vitamin C, Alpha Lipoic Acid",
            warnings: "Sulfur taste during IV push; Mild headache"
        ),
        PeptideInfo(
            name: "NAC", aliases: ["nac", "n-acetyl cysteine"],
            category: "Detox", defaultDose: "600-1800 mg", timing: "AM",
            frequency: "1-2x daily", injectionSite: "Oral", cycleLength: "Ongoing or cycles",
            benefit: "Glutathione replenishment",
            mechanism: "Provides cysteine for glutathione synthesis (rate-limiting step). Directly scavenges free radicals via sulfhydryl group. Chelates mercury, lead, and a",
            instructions: "Oral capsule or IV (hospital)",
            storage: "Room temperature. Protect from moisture (hygroscopic).",
            stackNotes: "Glutathione Iv, Alpha Lipoic Acid, Vitamin C",
            warnings: "GI discomfort; Sulfur smell/taste"
        ),
        PeptideInfo(
            name: "EDTA Chelation", aliases: ["edta chelation", "calcium disodium edta (cana2edta)"],
            category: "Detox", defaultDose: "1.5-3g IV over 1-3 hours", timing: "AM",
            frequency: "Weekly or biweekly", injectionSite: "As directed", cycleLength: "20-40 sessions",
            benefit: "Lead and heavy metal removal",
            mechanism: "Hexadentate chelator forming stable complexes with Pb²⁺, Cd²⁺, Hg²⁺, and Ca²⁺ from arterial plaque. Metal-EDTA complexes are water-soluble and excrete",
            instructions: "Intravenous infusion",
            storage: "Room temperature. Sterile vials.",
            stackNotes: "Nac, Glutathione Iv, Vitamin C",
            warnings: "Mineral depletion (zinc, calcium, magnesium); Kidney stress"
        ),
        PeptideInfo(
            name: "Activated Charcoal", aliases: ["activated charcoal", "activated charcoal (binder)"],
            category: "Detox", defaultDose: "500-1000 mg", timing: "AM",
            frequency: "1-2x daily away from meals/supplements", injectionSite: "Oral", cycleLength: "Short-term (1-2 weeks) or as-needed",
            benefit: "Mycotoxin binding (mold exposure)",
            mechanism: "Adsorbs toxins via van der Waals forces on its massive activated surface area. Binds mycotoxins (aflatoxin, ochratoxin), bacterial endotoxins (LPS), p",
            instructions: "Oral capsule or powder",
            storage: "Room temperature. Keep sealed (adsorbs ambient chemicals).",
            stackNotes: "Glutathione Iv, Bpc 157 Oral, Butyrate",
            warnings: "Constipation; Black stools"
        ),
        PeptideInfo(
            name: "PQQ", aliases: ["pqq", "pyrroloquinoline quinone (biopqq)"],
            category: "Detox", defaultDose: "10-20 mg", timing: "AM",
            frequency: "Daily", injectionSite: "Oral", cycleLength: "Ongoing",
            benefit: "Mitochondrial biogenesis (new mitochondria)",
            mechanism: "Activates PGC-1α (master mitochondrial biogenesis regulator) via CREB phosphorylation. Catalytic antioxidant that undergoes 20,000+ redox cycles vs on",
            instructions: "Oral capsule",
            storage: "Room temperature. Protect from moisture.",
            stackNotes: "Coq10, Nad Plus, Alpha Lipoic Acid",
            warnings: "Mild headache (initial); Vivid dreams"
        ),
        PeptideInfo(
            name: "HMG", aliases: ["hmg", "human menopausal gonadotropin (menotropins)"],
            category: "Fertility", defaultDose: "75-150 IU", timing: "AM",
            frequency: "3x weekly (men) or daily (women, stimulation)", injectionSite: "Subcutaneous", cycleLength: "3-6 months (men); 8-12 days (women IVF)",
            benefit: "Spermatogenesis restoration",
            mechanism: "FSH component directly stimulates Sertoli cells to support spermatogenesis in men, and granulosa cells for follicle growth in women. LH component stim",
            instructions: "Intramuscular or subcutaneous injection",
            storage: "Refrigerate (2-8°C). Reconstituted: use within 28 days.",
            stackNotes: "Hcg, Gonadorelin, Clomiphene Citrate",
            warnings: "Injection site pain; Ovarian hyperstimulation (women)"
        ),
        PeptideInfo(
            name: "Letrozole", aliases: ["letrozole", "letrozole (femara)"],
            category: "Fertility", defaultDose: "2.5-7.5 mg (women, day 3-7); 0.5-2.5 mg (men, 2-3x/week)", timing: "AM",
            frequency: "Cyclic (women) or 2-3x weekly (men)", injectionSite: "Oral", cycleLength: "Per cycle (women); ongoing (men)",
            benefit: "Ovulation induction (PCOS)",
            mechanism: "Reversibly inhibits aromatase (CYP19A1), blocking conversion of androgens to estrogens. In women, transient estrogen reduction triggers hypothalamic G",
            instructions: "Oral tablet",
            storage: "Room temperature.",
            stackNotes: "Hcg, Hmg, Gonadorelin",
            warnings: "Hot flashes; Joint pain"
        ),
        PeptideInfo(
            name: "HCG (Fertility)", aliases: ["hcg fertility", "hcg for ovulation trigger (pregnyl/ovidrel)"],
            category: "Fertility", defaultDose: "5000-10,000 IU (Pregnyl) or 250 mcg (Ovidrel)", timing: "AM",
            frequency: "Single injection timed to follicle maturity", injectionSite: "Subcutaneous", cycleLength: "Per cycle",
            benefit: "Precise ovulation timing",
            mechanism: "Binds LH/CG receptors on the dominant follicle, triggering resumption of meiosis in the oocyte, luteinization of granulosa cells, and follicular ruptu",
            instructions: "Subcutaneous or intramuscular",
            storage: "Refrigerate. Reconstituted: use within 30 days.",
            stackNotes: "Letrozole, Hmg, Progesterone",
            warnings: "Ovarian hyperstimulation risk; Bloating"
        ),
        PeptideInfo(
            name: "PEA", aliases: ["pea", "palmitoylethanolamide"],
            category: "Pain", defaultDose: "300-1200 mg", timing: "AM",
            frequency: "2-3x daily", injectionSite: "Oral", cycleLength: "2-3 months minimum for chronic pain",
            benefit: "Chronic pain reduction",
            mechanism: "Activates PPARα nuclear receptors for anti-inflammatory gene transcription. Inhibits mast cell degranulation. Enhances endocannabinoid tone by inhibit",
            instructions: "Oral (micronized preferred)",
            storage: "Room temperature. Protect from heat.",
            stackNotes: "Naltrexone Low Dose, Bpc 157, Omega 3",
            warnings: "Mild GI discomfort (rare); Generally extremely well-tolerated"
        ),
        PeptideInfo(
            name: "Diclofenac Topical", aliases: ["diclofenac topical", "diclofenac sodium topical gel (voltaren)"],
            category: "Pain", defaultDose: "4g gel (1% or 2%) per joint", timing: "AM",
            frequency: "3-4x daily", injectionSite: "Topical", cycleLength: "As needed or 2-4 week courses",
            benefit: "Localized pain relief",
            mechanism: "Inhibits cyclooxygenase-1 and -2 (COX-1/2) locally in tissue, reducing prostaglandin E2 synthesis at the inflammation site. Topical delivery achieves ",
            instructions: "Topical gel",
            storage: "Room temperature.",
            stackNotes: "Bpc 157, Tb 500, Pea",
            warnings: "Skin irritation at application site; Dryness/peeling"
        ),
        PeptideInfo(
            name: "Pentosan (Joint Pain)", aliases: ["pentosan polysulfate pain", "pentosan polysulfate sodium (cartrophen)"],
            category: "Pain", defaultDose: "2-3 mg/kg SC (veterinary extrapolation) or 100mg oral 3x/day", timing: "AM",
            frequency: "Weekly SC injections (4-6 course) or daily oral", injectionSite: "Subcutaneous", cycleLength: "6-week SC course; 3-6 months oral",
            benefit: "Cartilage protection and repair",
            mechanism: "Inhibits matrix metalloproteinases (MMPs) and aggrecanases that degrade cartilage. Stimulates hyaluronic acid production by synoviocytes. Promotes pro",
            instructions: "Subcutaneous injection or oral capsule",
            storage: "Room temperature. Sterile multi-use vial.",
            stackNotes: "Bpc 157, Ghk Cu, Tb 500",
            warnings: "Mild bleeding risk (anti-coagulant properties); Injection site bruising"
        ),
        PeptideInfo(
            name: "Dutasteride", aliases: ["dutasteride", "dutasteride (avodart)"],
            category: "Hair", defaultDose: "0.5 mg", timing: "AM",
            frequency: "Daily", injectionSite: "Oral", cycleLength: "6-12 months minimum for visible results",
            benefit: "Superior DHT suppression vs finasteride",
            mechanism: "Inhibits both type I and type II 5-alpha reductase isoenzymes, reducing serum DHT by ~90% and scalp DHT by ~50%. Prevents miniaturization of androgen-",
            instructions: "Oral capsule",
            storage: "Room temperature. Do not handle if pregnant (teratogenic risk).",
            stackNotes: "Minoxidil, Ghk Cu Topical, Ru 58841",
            warnings: "Sexual side effects (5-7%); Decreased libido"
        ),
        PeptideInfo(
            name: "Finasteride", aliases: ["finasteride", "finasteride (propecia/proscar)"],
            category: "Hair", defaultDose: "1 mg (hair) or 5 mg (prostate)", timing: "AM",
            frequency: "Daily", injectionSite: "Oral", cycleLength: "12+ months for full assessment",
            benefit: "Halts hair loss progression (90% of men)",
            mechanism: "Selectively inhibits type II 5-alpha reductase (predominant in hair follicles), reducing conversion of testosterone to dihydrotestosterone. Serum DHT ",
            instructions: "Oral tablet",
            storage: "Room temperature. Do not handle crushed tablets if pregnant.",
            stackNotes: "Minoxidil, Ghk Cu Topical, Biotin Injection",
            warnings: "Decreased libido (2-3%); Erectile dysfunction (1-2%)"
        ),
        PeptideInfo(
            name: "RU-58841", aliases: ["ru 58841", "ru-58841 (psk-3841)"],
            category: "Hair", defaultDose: "50-100 mg in 1mL vehicle", timing: "AM",
            frequency: "Daily application to scalp", injectionSite: "Topical", cycleLength: "Ongoing",
            benefit: "Local anti-androgen (no systemic effects)",
            mechanism: "Non-steroidal androgen receptor antagonist with high binding affinity. Applied topically, penetrates to dermal papilla cells where it blocks DHT-AR co",
            instructions: "Topical (dissolved in ethanol/PG vehicle)",
            storage: "Powder: -20°C. Solution: refrigerate, use within 1-2 weeks.",
            stackNotes: "Minoxidil, Finasteride, Ghk Cu Topical",
            warnings: "Scalp irritation; Dryness"
        ),
        PeptideInfo(
            name: "Minoxidil", aliases: ["minoxidil", "minoxidil (rogaine)"],
            category: "Hair", defaultDose: "5% topical (1mL 2x/day) or 2.5-5 mg oral", timing: "AM",
            frequency: "Twice daily (topical) or once daily (oral)", injectionSite: "Topical", cycleLength: "Ongoing (lifelong for maintenance)",
            benefit: "Stimulates new hair growth",
            mechanism: "Opens ATP-sensitive potassium channels in vascular smooth muscle and hair follicle cells. Increases blood flow and nutrient delivery to follicles. Pro",
            instructions: "Topical solution/foam or oral tablet",
            storage: "Room temperature. Topical: keep away from heat/flame.",
            stackNotes: "Finasteride, Ru 58841, Ghk Cu Topical",
            warnings: "Initial shedding (temporary); Scalp irritation (topical)"
        ),
        PeptideInfo(
            name: "GHK-Cu Topical", aliases: ["ghk cu topical", "ghk-cu copper peptide (topical/scalp)"],
            category: "Hair", defaultDose: "1-2 mg/mL in scalp solution or serum", timing: "AM",
            frequency: "Daily application", injectionSite: "Subcutaneous", cycleLength: "3-6 months minimum",
            benefit: "Follicle stem cell activation",
            mechanism: "Activates genes for hair growth including VEGF, FGF, and nerve growth factor at the follicular level. Stimulates dermal papilla cell proliferation. Ex",
            instructions: "Topical scalp serum or mesotherapy injection",
            storage: "Refrigerate serum (2-8°C). Protect from light.",
            stackNotes: "Minoxidil, Finasteride, Ru 58841",
            warnings: "Mild scalp tingling; Blue/green staining (high concentrations)"
        ),
        PeptideInfo(
            name: "TB-4 Topical (Hair)", aliases: ["tb4 topical", "thymosin beta-4 topical (hair growth)"],
            category: "Hair", defaultDose: "50-200 mcg per scalp application or 0.1% solution", timing: "AM",
            frequency: "3x weekly", injectionSite: "Subcutaneous", cycleLength: "3-6 months",
            benefit: "Hair follicle stem cell activation",
            mechanism: "Promotes migration and differentiation of hair follicle stem cells via actin sequestration and cell motility enhancement. Activates quiescent stem cel",
            instructions: "Topical serum or mesotherapy (intradermal injection)",
            storage: "Lyophilized: -20°C. Reconstituted serum: 2-8°C, use within 2 weeks.",
            stackNotes: "Ghk Cu Topical, Minoxidil, Finasteride",
            warnings: "Injection site discomfort (mesotherapy); Mild scalp redness"
        )
    ]

    // MARK: - Popular Stacks (8 stacks)

    static let stacks: [PeptideStack] = [
        PeptideStack(
            name: "KLOW Stack", aliases: ["klow stack", "klow"],
            purpose: "Advanced regenerative and anti-inflammatory blend combining GHK-Cu, KPV, BPC-157, and TB-500",
            peptides: ["GHK-Cu", "KPV", "BPC-157", "TB-500"],
            description: "Multi-pathway regenerative approach: GHK-Cu activates collagen synthesis and attracts repair cells. KPV inhibits NF-κB to reduce systemic inflammation. BPC-157 promotes angiogenesis. TB-500 upregulates actin for cell migration.",
            cycleLength: "8-12 weeks",
            notes: "GHK-Cu 200mcg + KPV 500mcg + BPC-157 500mcg + TB-500 2.5mg. Daily (BPC/KPV), 2-3x/week (TB-500/GHK-Cu). Subcutaneous injection. Stacks well with Thymosin Alpha-1, Epithalon, NAD+."
        ),
        PeptideStack(
            name: "GLOW Stack", aliases: ["glow stack", "glow"],
            purpose: "Skin rejuvenation, inflammation reduction, and tissue healing combining GHK-Cu, BPC-157, and TB-500",
            peptides: ["GHK-Cu", "BPC-157", "TB-500"],
            description: "GHK-Cu activates collagen synthesis, attracts immune and stem cells, remodels extracellular matrix. BPC-157 promotes angiogenesis and upregulates VEGF. TB-500 enhances cell migration and reduces pro-inflammatory cytokines.",
            cycleLength: "8-12 weeks",
            notes: "GHK-Cu 200mcg + BPC-157 500mcg + TB-500 2.5mg. GHK-Cu/BPC daily, TB-500 2-3x/week. Subcutaneous injection. Stacks well with Matrixyl, Argireline, Epithalon. Half-lives: GHK-Cu ~2h, BPC-157 ~4h, TB-500 ~6h."
        ),
        PeptideStack(
            name: "Wolverine Stack", aliases: ["wolverine stack"],
            purpose: "Named after the Marvel character for its regenerative properties, the Wolverine stack is the gold st",
            peptides: ["Ghk Cu", "Pentosan Polysulfate", "Thymosin Beta 4"],
            description: "BPC-157 upregulates VEGF and promotes localized angiogenesis at injury sites. TB-500 upregulates actin expression, promoting cell migration and reduci",
            cycleLength: "6-8 weeks",
            notes: "Named after the Marvel character for its regenerative properties, the Wolverine stack is the gold standard healing combination. BPC-157 provides local"
        ),
        PeptideStack(
            name: "Superman Stack", aliases: ["superman stack"],
            purpose: "The premier growth hormone optimization stack combining the three most effective GH-releasing compou",
            peptides: ["Tesamorelin", "Sermorelin", "Bpc 157"],
            description: "CJC-1295 (no DAC) mimics GHRH for pituitary stimulation. Ipamorelin acts as a selective ghrelin receptor agonist for GH release without cortisol/prola",
            cycleLength: "12-16 weeks",
            notes: "The premier growth hormone optimization stack combining the three most effective GH-releasing compounds. CJC-1295 provides sustained GHRH stimulation,"
        ),
        PeptideStack(
            name: "Apollo Stack", aliases: ["apollo stack"],
            purpose: "An aggressive fat loss and metabolic optimization stack. Combines GLP-1 receptor agonism for appetit",
            peptides: ["Aod 9604", "Tirzepatide", "Cjc 1295"],
            description: "Semaglutide activates GLP-1 receptors for appetite/glucose control. 5-Amino-1MQ inhibits NNMT to boost NAD+ and cellular energy. MOTS-c activates AMPK",
            cycleLength: "16-24 weeks",
            notes: "An aggressive fat loss and metabolic optimization stack. Combines GLP-1 receptor agonism for appetite suppression, NNMT inhibition for cellular metabo"
        ),
        PeptideStack(
            name: "Nootropic God Stack", aliases: ["nootropic god stack"],
            purpose: "The most potent cognitive enhancement stack combining four powerful nootropic peptides. Semax for fo",
            peptides: ["Noopept", "Nsi 189", "P21", "Cortagen"],
            description: "Semax upregulates BDNF/NGF expression and enhances dopaminergic/serotonergic transmission. Selank modulates GABA and reduces anxiety. Dihexa is a pote",
            cycleLength: "4-8 weeks cycled",
            notes: "The most potent cognitive enhancement stack combining four powerful nootropic peptides. Semax for focus and BDNF, Selank for anxiolysis and mood, Dihe"
        ),
        PeptideStack(
            name: "Immortality Stack", aliases: ["immortality stack"],
            purpose: "The ultimate longevity and anti-aging stack targeting the primary hallmarks of aging. Epithalon for ",
            peptides: ["Mots C", "Humanin", "Thymosin Alpha 1"],
            description: "Epithalon activates telomerase to maintain telomere length. NAD+ restores age-declined sirtuins and PARP activity. SS-31 (Elamipretide) stabilizes mit",
            cycleLength: "10-20 day cycles, 3-4x yearly",
            notes: "The ultimate longevity and anti-aging stack targeting the primary hallmarks of aging. Epithalon for telomere maintenance, NAD+ for cellular energy res"
        ),
        PeptideStack(
            name: "Performance Stack", aliases: ["performance stack"],
            purpose: "The most potent muscle growth and athletic performance stack combining myostatin inhibition, anaboli",
            peptides: ["Bpc 157", "Tb 500", "Mk 677"],
            description: "Follistatin-344 binds and neutralizes myostatin, removing the genetic brake on muscle growth. IGF-1 LR3 activates Akt/mTOR for protein synthesis. MGF ",
            cycleLength: "6-12 weeks cycled",
            notes: "The most potent muscle growth and athletic performance stack combining myostatin inhibition, anabolic growth factors, satellite cell activation, and g"
        )
    ]

    // MARK: - Lookup

    static func find(_ name: String) -> PeptideInfo? {
        let lower = name.lowercased()
        return database.first { info in
            info.name.lowercased() == lower ||
            info.aliases.contains(where: { $0.lowercased() == lower })
        }
    }

    static func fuzzyMatch(_ query: String) -> [PeptideInfo] {
        let lower = query.lowercased()
        return database.filter { info in
            info.name.lowercased().contains(lower) ||
            info.aliases.contains(where: { $0.lowercased().contains(lower) }) ||
            info.category.lowercased().contains(lower) ||
            info.benefit.lowercased().contains(lower)
        }
    }

    static func findStack(_ name: String) -> PeptideStack? {
        let lower = name.lowercased()
        return stacks.first { stack in
            stack.name.lowercased() == lower ||
            stack.name.lowercased().contains(lower) ||
            stack.aliases.contains(where: { $0.lowercased() == lower || $0.lowercased().contains(lower) })
        }
    }

    static func stacksContaining(_ peptideName: String) -> [PeptideStack] {
        stacks.filter { stack in
            stack.peptides.contains(where: { $0.lowercased().contains(peptideName.lowercased()) })
        }
    }

    // MARK: - Pros & Cons

    static func prosAndCons(for name: String) -> (pros: [String], cons: [String]) {
        let lower = name.lowercased()
        if let entry = peptideProsCons[lower] {
            return entry
        }
        if let info = find(name) {
            let derivedPros = derivePros(from: info)
            let derivedCons = deriveCons(from: info)
            return (derivedPros, derivedCons)
        }
        return ([], [])
    }

    private static func derivePros(from info: PeptideInfo) -> [String] {
        var pros: [String] = []
        let benefit = info.benefit.lowercased()
        if benefit.contains("heal") || benefit.contains("repair") { pros.append("Accelerates tissue healing and repair") }
        if benefit.contains("fat") || benefit.contains("weight") { pros.append("Supports fat loss and body composition") }
        if benefit.contains("muscle") || benefit.contains("strength") { pros.append("Promotes muscle growth and strength") }
        if benefit.contains("sleep") { pros.append("Improves sleep quality") }
        if benefit.contains("cognit") || benefit.contains("brain") || benefit.contains("focus") { pros.append("Enhances cognitive function") }
        if benefit.contains("immune") { pros.append("Strengthens immune system") }
        if benefit.contains("skin") || benefit.contains("hair") || benefit.contains("anti-aging") { pros.append("Anti-aging benefits for skin and appearance") }
        if benefit.contains("inflam") { pros.append("Reduces inflammation") }
        if benefit.contains("recovery") { pros.append("Enhances recovery from training") }
        if benefit.contains("growth hormone") || benefit.contains("gh") { pros.append("Stimulates natural growth hormone release") }
        if benefit.contains("libido") || benefit.contains("sexual") { pros.append("May improve sexual function") }
        if benefit.contains("energy") { pros.append("Boosts energy levels") }
        if pros.isEmpty { pros.append(info.benefit) }
        return pros
    }

    private static func deriveCons(from info: PeptideInfo) -> [String] {
        var cons: [String] = []
        cons.append("Not FDA-approved — research compound")
        cons.append("Requires subcutaneous injection")
        let warnings = info.warnings.lowercased()
        if warnings.contains("nausea") { cons.append("May cause nausea") }
        if warnings.contains("headache") { cons.append("Headaches reported") }
        if warnings.contains("water retention") || warnings.contains("bloat") { cons.append("Water retention or bloating") }
        if warnings.contains("cancer") || warnings.contains("tumor") { cons.append("Theoretical concern with cancer history") }
        if warnings.contains("blood sugar") || warnings.contains("insulin") { cons.append("May affect blood sugar levels") }
        if warnings.contains("blood pressure") { cons.append("May affect blood pressure") }
        if warnings.contains("fatigue") || warnings.contains("tiredness") { cons.append("May cause fatigue initially") }
        if !warnings.contains("no significant") && !warnings.isEmpty {
            let cleaned = info.warnings.trimmingCharacters(in: .whitespaces)
            if !cons.contains(cleaned) && cleaned.count < 100 {
                cons.append(cleaned)
            }
        }
        return cons
    }

    private static let peptideProsCons: [String: (pros: [String], cons: [String])] = [
        "bpc-157": (
            pros: ["Dramatically accelerates tendon and ligament healing", "Heals gut lining (IBD, leaky gut, ulcers)", "Protects organs from toxin damage", "Reduces systemic inflammation", "Promotes new blood vessel formation", "Neuroprotective — may help brain injuries", "Can be taken orally for gut-specific healing"],
            cons: ["Not FDA-approved — mostly animal research", "Injection site pain and irritation", "Possible nausea or dizziness", "Unknown long-term effects in humans", "Theoretical cancer risk (promotes angiogenesis)", "Quality varies between peptide sources", "Requires reconstitution and sterile technique"]
        ),
        "tb-500": (
            pros: ["Systemic tissue repair throughout the body", "Reduces inflammation and scar tissue", "Promotes hair regrowth", "Improves flexibility", "Accelerates wound healing", "Works synergistically with BPC-157"],
            cons: ["Theoretical cancer concern (cell proliferation)", "Not FDA-approved", "Injection site reactions", "Headaches and fatigue initially", "Expensive", "Limited human trial data", "May cause temporary head rush"]
        ),
        "ipamorelin": (
            pros: ["Cleanest GH secretagogue with fewest side effects", "Improves deep sleep quality", "Promotes fat loss", "Enhances recovery", "Anti-aging effects (skin, collagen)", "Does not significantly increase cortisol or prolactin"],
            cons: ["Increased hunger (ghrelin pathway)", "Water retention", "Tingling in extremities", "Headaches", "Joint pain at high doses", "Must fast 2h before", "Can worsen insulin resistance if overdosed"]
        ),
        "cjc-1295": (
            pros: ["Extends GH release duration", "Powerful synergy with Ipamorelin", "Promotes deep recovery", "Improves body composition", "Enhances sleep architecture", "Long-lasting effects"],
            cons: ["Water retention and facial puffiness", "Flushing and warmth post-injection", "Headaches and dizziness", "Joint pain/carpal tunnel possible", "DAC version causes constant elevated GH", "Must be fasted", "Not FDA-approved"]
        ),
        "ghk-cu": (
            pros: ["Powerful skin regeneration and anti-aging", "Stimulates collagen and elastin production", "Reduces fine lines and wrinkles", "Promotes wound healing", "Anti-inflammatory", "Can be used topically or injected", "Promotes hair growth"],
            cons: ["Injection site irritation", "Copper taste in mouth", "May worsen copper overload conditions (Wilson's disease)", "Results take weeks to appear", "Not FDA-approved for cosmetic use", "Can cause skin discoloration at injection site"]
        ),
        "cerebrolysin": (
            pros: ["Potent neurotrophic effects (BDNF, NGF)", "Used clinically in Europe for stroke/TBI recovery", "Improves memory and cognitive function", "Neuroprotective properties", "May help dementia and Alzheimer's", "Supports nerve regeneration"],
            cons: ["Must be injected (IM or IV)", "Headaches and dizziness", "Nausea and vertigo", "Allergic reactions possible (porcine-derived)", "Not FDA-approved in the US", "Expensive and hard to source", "Fever and flu-like symptoms reported"]
        ),
        "retatrutide": (
            pros: ["Triple-agonist: GLP-1, GIP, and glucagon receptors", "May produce greater weight loss than semaglutide", "Improves insulin sensitivity", "Reduces appetite significantly", "May reduce liver fat", "Cardiovascular benefits"],
            cons: ["Severe nausea and vomiting (common)", "Diarrhea and constipation", "Injection site reactions", "Not yet FDA-approved (clinical trials)", "Risk of gallstones with rapid weight loss", "Muscle loss without resistance training", "Thyroid C-cell tumor risk (animal studies)", "Pancreatitis risk"]
        ),
        "semaglutide": (
            pros: ["FDA-approved for weight management and diabetes", "Significant weight loss (15-20% body weight)", "Reduces cardiovascular risk", "Improves insulin sensitivity", "Reduces food noise and cravings", "Once-weekly injection convenience"],
            cons: ["Severe nausea (especially dose escalation)", "Vomiting, diarrhea, constipation", "Risk of pancreatitis", "Gallbladder problems", "Thyroid C-cell tumor concern", "Muscle loss without exercise", "Face aging ('Ozempic face')", "Expensive without insurance", "Weight regain when stopped"]
        ),
        "tirzepatide": (
            pros: ["Dual GLP-1/GIP agonist — more effective than semaglutide", "Up to 22% body weight reduction", "Significantly improves A1C", "Reduces cardiovascular risk", "May preserve more muscle than GLP-1 alone", "Reduces liver fat"],
            cons: ["GI side effects (nausea, vomiting, diarrhea)", "Risk of pancreatitis", "Gallbladder issues", "Thyroid tumor concern (animal data)", "Very expensive", "Injection site reactions", "Muscle loss still possible", "Long-term safety data still emerging"]
        ),
        "pt-141": (
            pros: ["Directly acts on brain (melanocortin receptors) for sexual arousal", "Works when PDE5 inhibitors (Viagra) fail", "Effective for both men and women", "Treats hypoactive sexual desire disorder", "Fast onset (1-2 hours)"],
            cons: ["Nausea (very common, sometimes severe)", "Flushing and facial redness", "Headaches", "Elevated blood pressure", "Can cause skin darkening (melanocyte activation)", "Not for use with cardiovascular conditions", "Fatigue after use"]
        ),
        "selank": (
            pros: ["Reduces anxiety without sedation", "Enhances memory and learning", "Immunomodulatory benefits", "No addiction potential", "Intranasal administration (no injection)", "Neuroprotective", "Improves mood stability"],
            cons: ["Limited Western research (developed in Russia)", "Effects can be subtle", "Fatigue in some users", "Possible allergic reactions", "Short half-life requires multiple daily doses", "Hard to source reliable products"]
        ),
        "semax": (
            pros: ["Powerful nootropic effects (focus, memory)", "Neuroprotective after stroke/TBI", "Increases BDNF", "Reduces anxiety", "Intranasal — no injection needed", "Well-studied in Russia with clinical use"],
            cons: ["Hair loss reported by some users", "Irritability or overstimulation", "Headaches", "Insomnia if used late", "Limited availability outside Russia", "Short duration of action", "May increase appetite"]
        ),
        "epitalon": (
            pros: ["May lengthen telomeres (anti-aging)", "Activates telomerase enzyme", "Improves sleep quality", "Antioxidant properties", "May slow biological aging", "Used in Russian gerontology research"],
            cons: ["Very limited human research", "Not FDA-approved", "Mechanism not fully validated", "Expensive", "Requires injection", "Long-term safety unknown", "Results are difficult to measure"]
        ),
        "mots-c": (
            pros: ["Mitochondrial peptide — improves metabolic function", "Enhances exercise capacity", "Improves insulin sensitivity", "May prevent age-related metabolic decline", "Reduces fat accumulation", "Promotes cellular energy production"],
            cons: ["Very early-stage research", "Not FDA-approved", "Limited human data", "Requires injection", "Expensive", "Optimal dosing unclear", "Long-term effects unknown"]
        ),
        "ss-31": (
            pros: ["Targets mitochondria directly", "Reduces oxidative stress at source", "May reverse age-related cellular decline", "Cardioprotective effects", "Improves kidney function in studies", "Potential for neurodegenerative diseases"],
            cons: ["Extremely limited availability", "Still in clinical trials", "Requires injection", "Very expensive", "Limited dosing information", "Long-term safety unknown"]
        ),
    ]
}
