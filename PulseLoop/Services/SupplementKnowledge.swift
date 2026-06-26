import Foundation
import os

struct SupplementInfo: Codable {
    let name: String
    let aliases: [String]
    let category: String
    let defaultDose: String
    let emoji: String
    let timing: String
    let benefit: String
    let mechanism: String
    let bestTimeReason: String
    let stackNotes: String
    let interactionNotes: String
    let pros: [String]
    let cons: [String]
}

struct Interaction: Identifiable {
    let id = UUID()
    let itemName: String
    let otherName: String
    let kind: InteractionKind
    let note: String
}

enum InteractionKind: String {
    case synergy = "Synergy"
    case conflict = "Conflict"
    case timing = "Timing"
}

struct MealInsight {
    let name: String
    let estimatedCalories: Int
    let estimatedProtein: Double?
    let estimatedCarbs: Double?
    let estimatedFat: Double?
    let emoji: String
    let supplementNote: String?
}

enum SupplementKnowledge {

    /// Public catalog. Loads from the bundled `supplements.json` resource when present,
    /// falling back to the in-source data below if the resource is missing or fails to decode.
    static let database: [SupplementInfo] = loadDatabase()

    private static func loadDatabase() -> [SupplementInfo] {
        guard let url = Bundle.main.url(forResource: "supplements", withExtension: "json") else {
            AppLog.persistence.notice("supplements.json not bundled; using in-source supplement data")
            return inSourceDatabase
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([SupplementInfo].self, from: data)
            return decoded.isEmpty ? inSourceDatabase : decoded
        } catch {
            AppLog.persistence.error("Failed to decode supplements.json: \(String(describing: error), privacy: .public); using in-source data")
            return inSourceDatabase
        }
    }

    static let inSourceDatabase: [SupplementInfo] = [
        SupplementInfo(
            name: "Vitamin D3", aliases: ["d3", "vitamin d", "cholecalciferol"],
            category: "vitamin", defaultDose: "2,000 IU", emoji: "☀️", timing: "AM",
            benefit: "Supports bone health, immune function, and mood regulation",
            mechanism: "Fat-soluble secosteroid that regulates calcium absorption and immune cell activity",
            bestTimeReason: "Take with a fat-containing meal for 50% better absorption",
            stackNotes: "Synergizes with K2 for proper calcium routing to bones instead of arteries",
            interactionNotes: "Space 2h from magnesium for optimal uptake",
            pros: ["Reduces risk of osteoporosis and fractures", "Strengthens immune defense against infections", "Improves mood and may reduce seasonal depression", "Supports healthy testosterone levels", "May reduce risk of certain cancers"],
            cons: ["Toxicity at very high doses (>10,000 IU/day long-term) causing hypercalcemia", "Nausea, vomiting, and kidney stones if over-supplemented", "Can cause arterial calcification without K2", "May interact with thiazide diuretics", "Blood tests needed to monitor levels"]
        ),
        SupplementInfo(
            name: "Vitamin K2", aliases: ["k2", "mk-7", "menaquinone"],
            category: "vitamin", defaultDose: "100 mcg", emoji: "bone", timing: "AM",
            benefit: "Directs calcium to bones and teeth, away from arteries",
            mechanism: "Activates osteocalcin (bone) and MGP (arterial) proteins",
            bestTimeReason: "Take with D3 and a fat source for synergistic absorption",
            stackNotes: "Essential companion to D3  -  prevents arterial calcification",
            interactionNotes: "May reduce effectiveness of blood thinners (warfarin)",
            pros: ["Prevents calcium buildup in arteries", "Strengthens bone density", "Reduces fracture risk significantly", "Supports dental health", "Synergizes with D3 for optimal calcium metabolism"],
            cons: ["Dangerous interaction with warfarin/blood thinners", "May cause blood clotting in those with clotting disorders", "Rare: nausea or upset stomach", "Limited research on very high doses", "Must be taken with fat for absorption"]
        ),
        SupplementInfo(
            name: "Omega-3", aliases: ["fish oil", "epa", "dha", "omega 3"],
            category: "supplement", defaultDose: "1,000 mg", emoji: "drop.fill", timing: "AM",
            benefit: "Reduces inflammation, supports brain and heart health",
            mechanism: "EPA/DHA integrate into cell membranes, modulating inflammatory pathways",
            bestTimeReason: "Take with meals to reduce fishy aftertaste and improve absorption",
            stackNotes: "Complements D3 absorption (provides fat vehicle)",
            interactionNotes: "May increase bleeding risk with blood thinners at high doses",
            pros: ["Significantly reduces systemic inflammation", "Lowers triglycerides by 15-30%", "Supports brain health and may reduce depression", "Protects cardiovascular system", "Improves joint mobility and reduces stiffness", "Supports healthy skin and reduces dryness"],
            cons: ["Fishy burps and aftertaste", "May increase bleeding risk at high doses (>3g/day)", "Possible interaction with blood thinners", "Can cause GI upset, diarrhea, or nausea", "Risk of oxidation if poorly stored (rancid oil is harmful)", "May raise LDL cholesterol slightly in some people"]
        ),
        SupplementInfo(
            name: "Magnesium", aliases: ["mag", "magnesium glycinate", "magnesium threonate"],
            category: "supplement", defaultDose: "400 mg", emoji: "moon.fill", timing: "PM",
            benefit: "Supports sleep quality, muscle relaxation, and 300+ enzymatic reactions",
            mechanism: "Cofactor for ATP production, GABA receptor agonist promoting calm",
            bestTimeReason: "PM dosing leverages calming effect for better sleep onset",
            stackNotes: "Pairs well with zinc and B6 for sleep (ZMA stack)",
            interactionNotes: "Space 2h from calcium and D3  -  they compete for absorption",
            pros: ["Improves sleep quality and reduces insomnia", "Relieves muscle cramps and tension", "Reduces anxiety and promotes calm", "Supports 300+ enzymatic reactions in the body", "May reduce migraine frequency", "Helps regulate blood pressure"],
            cons: ["Loose stools or diarrhea (especially oxide form)", "Can cause drowsiness — don't take before driving", "May lower blood pressure too much if already low", "Competes with calcium and zinc for absorption", "High doses can cause nausea", "Kidney patients should consult doctor first"]
        ),
        SupplementInfo(
            name: "Creatine", aliases: ["creatine monohydrate"],
            category: "supplement", defaultDose: "5 g", emoji: "figure.strengthtraining.traditional", timing: "AM",
            benefit: "Increases strength, power output, and cognitive performance",
            mechanism: "Replenishes phosphocreatine stores for rapid ATP regeneration",
            bestTimeReason: "Timing doesn't matter much  -  consistency is key. AM with food works well",
            stackNotes: "Safe to combine with most supplements. Pairs with protein for muscle gains",
            interactionNotes: "Stay well-hydrated. No significant negative interactions",
            pros: ["Increases strength and power output by 5-15%", "Enhances cognitive performance and memory", "One of the most researched supplements with strong safety profile", "Supports brain health and neuroprotection", "Increases lean muscle mass", "May benefit depression and mood"],
            cons: ["Water retention and initial weight gain (2-5 lbs)", "May cause bloating in some people", "Rare: stomach cramping if taken without water", "Theoretical kidney concern in those with pre-existing conditions", "Can cause muscle cramping if dehydrated", "Non-responders (~20%) see minimal benefit"]
        ),
        SupplementInfo(
            name: "Vitamin C", aliases: ["vit c", "ascorbic acid"],
            category: "vitamin", defaultDose: "500 mg", emoji: "drop.fill", timing: "AM",
            benefit: "Antioxidant, immune support, collagen synthesis, iron absorption",
            mechanism: "Electron donor that neutralizes free radicals and enables hydroxylation reactions",
            bestTimeReason: "AM with food to reduce GI irritation. Split doses if >1000mg",
            stackNotes: "Enhances iron absorption  -  take together if supplementing iron",
            interactionNotes: "High doses may reduce copper absorption",
            pros: ["Powerful antioxidant protecting against oxidative stress", "Boosts immune function and reduces cold duration", "Essential for collagen production (skin, joints)", "Dramatically improves iron absorption", "May reduce blood pressure", "Supports wound healing"],
            cons: ["GI upset, heartburn, and diarrhea at high doses (>2g)", "Kidney stones risk with chronic high doses", "May cause false readings on blood glucose tests", "Can reduce copper absorption long-term", "Iron overload risk if taken with iron in those with hemochromatosis", "Rebound scurvy if suddenly stopping very high doses"]
        ),
        SupplementInfo(
            name: "Zinc", aliases: ["zinc picolinate", "zinc glycinate"],
            category: "supplement", defaultDose: "15 mg", emoji: "shield.fill", timing: "PM",
            benefit: "Immune function, testosterone support, wound healing",
            mechanism: "Cofactor for 100+ enzymes, supports thymus function and T-cell maturation",
            bestTimeReason: "PM with magnesium for sleep support (ZMA effect)",
            stackNotes: "Pairs with magnesium and B6 for sleep. Take with copper long-term",
            interactionNotes: "Competes with copper and iron  -  space from iron supplements by 2h",
            pros: ["Strengthens immune system and shortens colds", "Supports healthy testosterone levels", "Accelerates wound healing", "Improves skin health and reduces acne", "Essential for taste and smell", "Supports prostate health"],
            cons: ["Nausea and vomiting if taken on empty stomach", "Copper deficiency with long-term use (>30mg/day)", "Metallic taste in mouth", "Can cause headaches", "Competes with iron absorption", "High doses (>40mg) may cause abdominal pain and diarrhea"]
        ),
        SupplementInfo(
            name: "Ashwagandha", aliases: ["ksm-66", "withania"],
            category: "supplement", defaultDose: "600 mg", emoji: "leaf.fill", timing: "PM",
            benefit: "Reduces cortisol, anxiety, and supports thyroid function",
            mechanism: "Adaptogen that modulates HPA axis and GABAergic signaling",
            bestTimeReason: "PM dosing maximizes cortisol reduction for better sleep",
            stackNotes: "Pairs with magnesium for enhanced relaxation",
            interactionNotes: "May potentiate thyroid medications  -  consult doctor if on levothyroxine",
            pros: ["Clinically shown to reduce cortisol by 23-30%", "Significantly reduces anxiety and stress", "Improves sleep quality", "Supports testosterone and fertility in men", "Enhances endurance and strength", "Improves thyroid function (T3/T4)"],
            cons: ["May cause drowsiness or sedation", "Can overstimulate thyroid — dangerous for hyperthyroid patients", "GI upset including diarrhea in some users", "May interact with immunosuppressants", "Not safe during pregnancy", "Rare cases of liver injury reported at high doses", "Can cause vivid dreams or emotional blunting"]
        ),
        SupplementInfo(
            name: "L-Theanine", aliases: ["theanine"],
            category: "supplement", defaultDose: "200 mg", emoji: "cup.and.saucer", timing: "AM",
            benefit: "Promotes calm focus without drowsiness, reduces caffeine jitters",
            mechanism: "Crosses BBB, increases alpha brain waves and GABA/serotonin/dopamine",
            bestTimeReason: "AM with caffeine for smooth, focused energy without anxiety",
            stackNotes: "Classic stack with caffeine (2:1 ratio theanine:caffeine)",
            interactionNotes: "Very safe. No known significant interactions",
            pros: ["Promotes relaxation without sedation", "Reduces caffeine jitters and anxiety", "Enhances focus and attention (alpha brain waves)", "Very safe with no known toxicity", "Improves sleep quality when taken at night", "May lower blood pressure gently"],
            cons: ["May cause drowsiness at high doses (>400mg)", "Can slightly lower blood pressure", "Possible headache in sensitive individuals", "May reduce effectiveness of stimulant medications", "Very mild effect — some people notice nothing", "Limited research on long-term daily high-dose use"]
        ),
        SupplementInfo(
            name: "NAC", aliases: ["n-acetyl cysteine", "n-acetylcysteine"],
            category: "supplement", defaultDose: "600 mg", emoji: "lungs.fill", timing: "AM",
            benefit: "Glutathione precursor, liver support, respiratory health, antioxidant",
            mechanism: "Provides cysteine for glutathione synthesis  -  the body's master antioxidant",
            bestTimeReason: "AM on empty stomach for best absorption, 30min before food",
            stackNotes: "Pairs with Vitamin C for enhanced antioxidant network",
            interactionNotes: "Take away from zinc  -  may chelate minerals. Space 1h from food",
            pros: ["Replenishes glutathione — the body's master antioxidant", "Protects liver from toxin damage (used in hospitals for acetaminophen OD)", "Thins mucus and improves respiratory health", "May reduce OCD and addictive behaviors", "Supports brain health and reduces oxidative stress", "Potential anti-aging benefits"],
            cons: ["Nausea, vomiting, and diarrhea (common at high doses)", "Unpleasant sulfur smell/taste", "May chelate zinc and other minerals — space apart", "Can cause headaches", "Rare: allergic reactions (rash, breathing issues)", "May interfere with certain chemotherapy drugs", "Can cause low blood pressure in some people"]
        ),
        SupplementInfo(
            name: "BPC-157", aliases: ["bpc157", "bpc 157", "body protection compound"],
            category: "peptide", defaultDose: "250 mcg", emoji: "syringe.fill", timing: "AM",
            benefit: "Accelerates tissue repair, gut healing, and tendon/ligament recovery",
            mechanism: "Upregulates growth factor receptors (VEGF, FGF) and nitric oxide pathways",
            bestTimeReason: "Inject subcutaneously AM near injury site or abdomen for systemic effect",
            stackNotes: "Often stacked with TB-500 for enhanced tissue repair",
            interactionNotes: "Avoid NSAIDs which may counteract healing pathways",
            pros: ["Dramatically accelerates tendon and ligament healing", "Heals gut lining (IBD, leaky gut, ulcers)", "Reduces inflammation systemically", "Protects organs from toxin damage", "Promotes angiogenesis (new blood vessel formation)", "Neuroprotective properties"],
            cons: ["Not FDA-approved — research mostly animal studies", "Injection site pain, redness, or irritation", "Possible nausea or dizziness", "Unknown long-term effects in humans", "Theoretical concern: could promote tumor growth via angiogenesis", "Quality/purity varies widely between sources", "Requires proper reconstitution knowledge"]
        ),
        SupplementInfo(
            name: "TB-500", aliases: ["tb500", "thymosin beta-4"],
            category: "peptide", defaultDose: "5 mg/week", emoji: "syringe.fill", timing: "AM",
            benefit: "Promotes tissue regeneration, reduces inflammation, hair regrowth",
            mechanism: "Upregulates actin, promoting cell migration and blood vessel formation",
            bestTimeReason: "Inject 2-3x per week subcutaneously. Morning for consistency",
            stackNotes: "Synergistic with BPC-157 for comprehensive tissue repair",
            interactionNotes: "Theoretical concern with active cancers  -  avoid if history of malignancy",
            pros: ["Powerful systemic tissue repair", "Reduces inflammation throughout the body", "Promotes hair regrowth", "Improves flexibility and reduces scar tissue", "Accelerates muscle and tendon recovery", "Promotes new blood vessel growth"],
            cons: ["Not FDA-approved — limited human clinical data", "Theoretical cancer risk (promotes cell proliferation)", "Injection site reactions (redness, swelling)", "Headaches reported by some users", "Fatigue or lethargy initially", "Expensive and requires sourcing from research companies", "May cause temporary head rush after injection"]
        ),
        SupplementInfo(
            name: "Ipamorelin", aliases: ["ipam"],
            category: "peptide", defaultDose: "200 mcg", emoji: "syringe.fill", timing: "PM",
            benefit: "Stimulates growth hormone release for recovery, fat loss, and sleep quality",
            mechanism: "Selective ghrelin mimetic that triggers pulsatile GH release from pituitary",
            bestTimeReason: "Before bed on empty stomach  -  aligns with natural GH pulse during deep sleep",
            stackNotes: "Often combined with CJC-1295 (no DAC) for amplified GH release",
            interactionNotes: "Fast 2h before injection. Avoid with food/carbs that spike insulin",
            pros: ["Stimulates natural growth hormone release", "Improves sleep quality and deep sleep", "Promotes fat loss while preserving muscle", "Enhances recovery from training", "Anti-aging benefits (skin, collagen, bone density)", "Fewer side effects than synthetic HGH"],
            cons: ["Increased hunger (ghrelin pathway)", "Water retention and bloating", "Tingling or numbness in extremities", "Headaches, especially initially", "Potential joint pain from GH increase", "Must fast 2h before for effectiveness", "Not FDA-approved for anti-aging use", "Can worsen insulin resistance if overdosed"]
        ),
        SupplementInfo(
            name: "CJC-1295", aliases: ["cjc", "cjc1295", "mod grf"],
            category: "peptide", defaultDose: "100 mcg", emoji: "syringe.fill", timing: "PM",
            benefit: "Extends growth hormone release duration for deeper recovery",
            mechanism: "GHRH analog that amplifies natural GH pulses without desensitization",
            bestTimeReason: "Before bed with Ipamorelin for synergistic GH pulse",
            stackNotes: "Standard combo with Ipamorelin (1:2 ratio CJC:Ipam)",
            interactionNotes: "Same fasting rules as Ipamorelin. Avoid insulin-spiking foods nearby",
            pros: ["Amplifies and extends natural GH pulses", "Synergizes powerfully with Ipamorelin", "Promotes deep recovery and tissue repair", "Improves body composition", "Enhances sleep architecture", "Anti-aging effects on skin and joints"],
            cons: ["Water retention and facial puffiness", "Increased cortisol possible", "Flushing and warmth after injection", "Headaches and dizziness", "Potential for joint pain/carpal tunnel at high doses", "Must be fasted for proper effect", "Not FDA-approved", "DAC version can cause constant elevated GH (less pulsatile, more side effects)"]
        ),
        SupplementInfo(
            name: "Iron", aliases: ["ferrous", "iron bisglycinate"],
            category: "supplement", defaultDose: "18 mg", emoji: "cross.vial.fill", timing: "AM",
            benefit: "Oxygen transport, energy production, cognitive function",
            mechanism: "Core component of hemoglobin and myoglobin for O2 delivery to tissues",
            bestTimeReason: "AM on empty stomach with vitamin C for 3x better absorption",
            stackNotes: "Always pair with Vitamin C. Consider with B12 if anemic",
            interactionNotes: "Competes with zinc, calcium, and magnesium  -  space 2h from each",
            pros: ["Eliminates fatigue from iron-deficiency anemia", "Improves oxygen delivery to muscles and brain", "Enhances cognitive function and concentration", "Supports immune system", "Essential for endurance athletes", "Improves hair growth when deficient"],
            cons: ["Constipation (very common)", "Nausea, vomiting, and stomach pain", "Black/dark stools", "Iron overload (hemochromatosis) is dangerous", "Oxidative damage if taken when not deficient", "Competes with zinc and calcium absorption", "Can stain teeth (liquid forms)", "Accidental overdose is dangerous in children"]
        ),
        SupplementInfo(
            name: "B12", aliases: ["methylcobalamin", "vitamin b12", "cobalamin"],
            category: "vitamin", defaultDose: "1,000 mcg", emoji: "bolt.fill", timing: "AM",
            benefit: "Energy production, nerve function, red blood cell formation",
            mechanism: "Coenzyme for methylation reactions and myelin synthesis",
            bestTimeReason: "AM to avoid potential sleep interference from energy boost",
            stackNotes: "Part of the B-complex family. Pairs with folate for methylation",
            interactionNotes: "Metformin depletes B12  -  supplement if taking metformin",
            pros: ["Eliminates fatigue from B12 deficiency", "Supports nerve health and prevents neuropathy", "Essential for red blood cell formation", "Improves mood and reduces depression symptoms", "Supports methylation (gene expression, detox)", "Safe even at high doses (water-soluble)"],
            cons: ["Acne breakouts reported by some users at high doses", "May cause anxiety or restlessness", "Can mask folate deficiency", "Rare: allergic reaction to injections", "Insomnia if taken too late in the day", "Potential interaction with certain antibiotics and anti-seizure meds"]
        ),
        SupplementInfo(
            name: "Probiotics", aliases: ["probiotic", "lactobacillus", "bifidobacterium"],
            category: "supplement", defaultDose: "50B CFU", emoji: "microbe", timing: "AM",
            benefit: "Gut microbiome balance, immune modulation, nutrient absorption",
            mechanism: "Live bacteria that colonize the gut, outcompeting pathogens and producing SCFAs",
            bestTimeReason: "AM on empty stomach  -  gastric acid is lowest, improving survival",
            stackNotes: "Pair with prebiotic fiber for better colonization",
            interactionNotes: "Space from antibiotics by 2-4h. Heat-sensitive  -  store properly",
            pros: ["Improves digestion and reduces bloating", "Strengthens immune system (70% in gut)", "May reduce anxiety and depression (gut-brain axis)", "Helps recover gut flora after antibiotics", "Reduces IBS symptoms", "May improve skin conditions (eczema, acne)"],
            cons: ["Initial gas and bloating (usually temporary)", "Can trigger histamine reactions in sensitive people", "Risk of infection in immunocompromised individuals", "May worsen SIBO symptoms", "Expensive for quality strains", "Die-off reactions (headache, fatigue) initially", "Strain-specific — wrong strain may not help"]
        ),
        SupplementInfo(
            name: "Collagen", aliases: ["collagen peptides", "hydrolyzed collagen"],
            category: "supplement", defaultDose: "10 g", emoji: "sparkles", timing: "AM",
            benefit: "Skin elasticity, joint health, gut lining integrity",
            mechanism: "Provides hydroxyproline and glycine as building blocks for connective tissue",
            bestTimeReason: "AM with vitamin C to enhance collagen synthesis",
            stackNotes: "Vitamin C is essential cofactor  -  always pair together",
            interactionNotes: "No significant interactions. Safe to combine with most supplements",
            pros: ["Improves skin elasticity and reduces wrinkles", "Reduces joint pain and stiffness", "Strengthens hair and nails", "Supports gut lining integrity", "May improve bone density", "Generally very safe and well-tolerated"],
            cons: ["Digestive upset (bloating, heartburn) in some people", "Bad taste or aftertaste with some brands", "May contain heavy metals if poorly sourced", "Not suitable for those with fish/shellfish allergies (marine collagen)", "Results take 8-12 weeks to notice", "Can cause a feeling of fullness"]
        ),
        SupplementInfo(
            name: "Melatonin", aliases: ["melatonin"],
            category: "supplement", defaultDose: "0.5 mg", emoji: "moon.fill", timing: "PM",
            benefit: "Regulates circadian rhythm, improves sleep onset",
            mechanism: "Binds MT1/MT2 receptors in SCN, signaling darkness to the brain",
            bestTimeReason: "30-60 min before desired sleep time. Less is more (0.3-1mg optimal)",
            stackNotes: "Pairs with magnesium and glycine for comprehensive sleep support",
            interactionNotes: "May interact with blood pressure meds and immunosuppressants",
            pros: ["Reduces time to fall asleep", "Helps reset circadian rhythm (jet lag, shift work)", "Powerful antioxidant", "May support immune function", "Safe for short-term use", "Useful for adjusting sleep schedule"],
            cons: ["Daytime grogginess if dose is too high", "Vivid dreams or nightmares", "Can disrupt natural melatonin production if overused", "Headaches and dizziness", "May worsen depression in some people", "Not effective for staying asleep (short half-life)", "Can interact with blood thinners and diabetes meds", "Tolerance can develop with nightly use"]
        ),
        SupplementInfo(
            name: "Berberine", aliases: ["berberine hcl"],
            category: "supplement", defaultDose: "500 mg", emoji: "leaf", timing: "AM",
            benefit: "Blood sugar regulation, gut health, cholesterol management",
            mechanism: "Activates AMPK pathway  -  similar mechanism to metformin",
            bestTimeReason: "With meals to blunt glucose spike. Split into 2-3 doses daily",
            stackNotes: "May pair with chromium for enhanced glucose control",
            interactionNotes: "Potent  -  interacts with many medications via CYP450 enzymes. Consult doctor",
            pros: ["Lowers blood sugar as effectively as metformin in studies", "Reduces LDL cholesterol and triglycerides", "Anti-inflammatory and antimicrobial", "Supports weight loss", "May improve fatty liver (NAFLD)", "Improves insulin sensitivity"],
            cons: ["GI distress: diarrhea, cramping, nausea (very common)", "Interacts with many drugs via CYP450 enzymes", "Can cause hypoglycemia if combined with diabetes meds", "May kill beneficial gut bacteria", "Contraindicated in pregnancy", "Can cause constipation in some people", "Should not combine with metformin (additive effects too strong)"]
        ),
        SupplementInfo(
            name: "Curcumin", aliases: ["turmeric", "curcumin"],
            category: "supplement", defaultDose: "500 mg", emoji: "circle.fill", timing: "AM",
            benefit: "Powerful anti-inflammatory, joint comfort, brain health",
            mechanism: "Inhibits NF-kB and COX-2 inflammatory pathways",
            bestTimeReason: "With food and black pepper (piperine) for 2000% better absorption",
            stackNotes: "Always take with piperine/BioPerine. Pairs with Omega-3 for inflammation",
            interactionNotes: "May thin blood  -  caution with anticoagulants",
            pros: ["One of nature's most powerful anti-inflammatories", "Reduces joint pain comparable to NSAIDs", "Neuroprotective — may reduce Alzheimer's risk", "Strong antioxidant properties", "May reduce cancer risk (multiple pathways)", "Improves endothelial function (heart health)"],
            cons: ["Very poor absorption without piperine/fat", "May thin blood — risky before surgery or with blood thinners", "Can cause stomach upset and acid reflux", "May worsen gallbladder issues", "Iron absorption may be reduced", "Yellow staining of teeth and surfaces", "Piperine increases absorption of many drugs (caution)"]
        ),
        SupplementInfo(
            name: "Lion's Mane", aliases: ["lions mane", "hericium"],
            category: "supplement", defaultDose: "1,000 mg", emoji: "allergens", timing: "AM",
            benefit: "Neurogenesis, memory, focus, nerve repair",
            mechanism: "Stimulates NGF (nerve growth factor) production for brain plasticity",
            bestTimeReason: "AM for cognitive benefits throughout the day",
            stackNotes: "Pairs with L-Theanine and caffeine for a nootropic stack",
            interactionNotes: "Generally very safe. May slightly lower blood sugar",
            pros: ["Stimulates nerve growth factor (NGF) for brain repair", "Improves memory and cognitive function", "May reduce mild anxiety and depression", "Supports nerve regeneration after injury", "Anti-inflammatory and antioxidant", "May help prevent neurodegenerative diseases"],
            cons: ["May cause itchy skin (increased NGF)", "Can slow blood clotting — caution before surgery", "GI discomfort in some people", "May lower blood sugar — monitor if diabetic", "Allergic reactions possible (mushroom allergy)", "Some users report reduced libido", "Quality varies enormously between brands"]
        ),
        SupplementInfo(
            name: "Glutathione", aliases: ["liposomal glutathione", "gsh"],
            category: "supplement", defaultDose: "500 mg", emoji: "flask.fill", timing: "AM",
            benefit: "Master antioxidant, detoxification, immune support, skin brightening",
            mechanism: "Tripeptide that neutralizes ROS and recycles other antioxidants (C, E)",
            bestTimeReason: "AM on empty stomach. Liposomal form for better oral bioavailability",
            stackNotes: "NAC is a precursor  -  taking both provides redundant glutathione support",
            interactionNotes: "May reduce chemotherapy effectiveness  -  avoid during active treatment",
            pros: ["The body's most powerful antioxidant", "Detoxifies liver and protects from environmental toxins", "Brightens skin and reduces hyperpigmentation", "Supports immune function", "Recycles vitamins C and E", "May slow aging at the cellular level"],
            cons: ["Poor oral bioavailability (need liposomal or IV form)", "Expensive for effective forms", "May interfere with chemotherapy drugs", "Bloating and cramping possible", "Can cause zinc depletion with long-term use", "May worsen asthma in some people (inhaled form)", "Limited evidence for oral supplementation effectiveness"]
        ),
        SupplementInfo(
            name: "CoQ10", aliases: ["coenzyme q10", "ubiquinol", "coq10"],
            category: "supplement", defaultDose: "200 mg", emoji: "❤️", timing: "AM",
            benefit: "Cellular energy, heart health, antioxidant, statin side-effect mitigation",
            mechanism: "Essential electron carrier in mitochondrial ATP production (Complex III)",
            bestTimeReason: "With a fat-containing meal for absorption. AM for energy benefits",
            stackNotes: "Essential if on statins (they deplete CoQ10). Pairs with PQQ",
            interactionNotes: "May reduce blood thinner effectiveness. Safe with most supplements",
            pros: ["Essential for mitochondrial energy production", "Protects heart health and improves cardiac function", "Counteracts statin-induced muscle pain and fatigue", "Powerful antioxidant", "May reduce migraine frequency", "Supports fertility (egg and sperm quality)", "Slows cellular aging"],
            cons: ["Insomnia if taken late in the day", "Mild GI upset (nausea, diarrhea)", "May reduce effectiveness of blood thinners (warfarin)", "Can lower blood pressure (caution if already low)", "Expensive for therapeutic doses", "Takes 4-12 weeks to notice benefits", "May interact with chemotherapy and blood pressure medications"]
        ),
        SupplementInfo(
            name: "Electrolytes", aliases: ["lmnt", "electrolyte", "sodium", "potassium"],
            category: "supplement", defaultDose: "1 packet", emoji: "drop.fill", timing: "AM",
            benefit: "Hydration, muscle function, nerve signaling, energy",
            mechanism: "Maintains osmotic balance and membrane potential for cellular function",
            bestTimeReason: "AM or pre/post workout. First thing AM helps with morning cortisol",
            stackNotes: "Pairs with creatine for enhanced hydration and performance",
            interactionNotes: "Caution with kidney disease or blood pressure medications",
            pros: ["Rapidly improves hydration and energy", "Prevents muscle cramps during exercise", "Supports nerve function and mental clarity", "Helps with keto/fasting headaches", "Improves athletic performance", "Reduces morning brain fog"],
            cons: ["Excess sodium can raise blood pressure", "May worsen kidney conditions", "Some people retain water/bloat", "Can cause nausea if too concentrated", "May interact with blood pressure medications", "Potassium excess can be dangerous (cardiac risk)"]
        ),
        SupplementInfo(
            name: "Tongkat Ali", aliases: ["tongkat", "longjack", "eurycoma"],
            category: "supplement", defaultDose: "400 mg", emoji: "tree.fill", timing: "AM",
            benefit: "Testosterone support, stress reduction, athletic performance",
            mechanism: "Reduces SHBG, freeing bound testosterone. Lowers cortisol via adaptogenic action",
            bestTimeReason: "AM on empty stomach for peak absorption. Cycle 5 days on, 2 off",
            stackNotes: "Pairs with Fadogia Agrestis for testosterone. Add zinc for support",
            interactionNotes: "May interact with hormone therapies and blood sugar medications",
            pros: ["Clinically shown to increase free testosterone", "Reduces cortisol and perceived stress", "Improves body composition and athletic performance", "May enhance libido and sexual function", "Supports mood and well-being", "Adaptogenic stress reduction"],
            cons: ["Insomnia and restlessness (especially at high doses)", "Can increase aggression or irritability", "May cause anxiety in sensitive individuals", "Not recommended during pregnancy/breastfeeding", "Potential liver toxicity at very high doses", "May interact with hormone-sensitive conditions", "Quality varies widely — many adulterated products"]
        ),
        SupplementInfo(
            name: "Fadogia Agrestis", aliases: ["fadogia"],
            category: "supplement", defaultDose: "600 mg", emoji: "leaf.fill", timing: "AM",
            benefit: "Supports luteinizing hormone and testosterone production",
            mechanism: "Stimulates Leydig cells to increase testosterone synthesis",
            bestTimeReason: "AM with Tongkat Ali. Cycle to avoid receptor desensitization",
            stackNotes: "Standard stack with Tongkat Ali for testosterone optimization",
            interactionNotes: "Limited safety data at high doses. Cycle on/off. Monitor liver enzymes",
            pros: ["May increase luteinizing hormone", "Supports testosterone production", "Enhances athletic performance", "Synergizes with Tongkat Ali", "May improve libido"],
            cons: ["Very limited human research — mostly animal studies", "Potential testicular toxicity at high doses (animal data)", "May cause liver enzyme elevation", "Unknown long-term safety profile", "Quality control issues with many products", "Should be cycled (not used continuously)", "May interact with hormone therapies"]
        ),
    ]

    // MARK: - Lookup

    static func find(_ query: String) -> SupplementInfo? {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        return database.first { info in
            info.name.lowercased() == q ||
            info.aliases.contains(where: { q.contains($0) || $0.contains(q) })
        }
    }

    static func fuzzyMatch(_ query: String) -> [SupplementInfo] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        let words = q.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        return database.filter { info in
            let nameMatch = words.contains(where: { info.name.lowercased().contains($0) })
            let aliasMatch = info.aliases.contains(where: { alias in
                words.contains(where: { alias.contains($0) || $0.contains(alias) })
            })
            return nameMatch || aliasMatch
        }
    }

    // MARK: - Interaction Engine

    private static let interactionPairs: [(a: String, b: String, kind: InteractionKind, note: String)] = [
        ("Vitamin D3", "Vitamin K2", .synergy, "K2 directs D3-absorbed calcium to bones, preventing arterial deposits"),
        ("Vitamin D3", "Magnesium", .timing, "Space 2h apart  -  they compete for absorption pathways"),
        ("Vitamin D3", "Omega-3", .synergy, "Omega-3 provides fat vehicle for D3 absorption"),
        ("Vitamin C", "Iron", .synergy, "Vitamin C increases iron absorption by up to 3x"),
        ("Vitamin C", "NAC", .synergy, "Both support the glutathione antioxidant network"),
        ("Zinc", "Iron", .conflict, "Compete for the same absorption transporters  -  space 2h apart"),
        ("Zinc", "Magnesium", .synergy, "ZMA stack  -  synergistic for sleep and recovery"),
        ("Calcium", "Iron", .conflict, "Calcium inhibits iron absorption  -  take at different meals"),
        ("Calcium", "Magnesium", .timing, "Compete for absorption  -  space by 2h or take at different meals"),
        ("Magnesium", "Ashwagandha", .synergy, "Combined calming effect on the nervous system for better sleep"),
        ("L-Theanine", "Lion's Mane", .synergy, "Nootropic stack  -  calm focus plus neurogenesis"),
        ("BPC-157", "TB-500", .synergy, "Comprehensive tissue repair  -  BPC for gut/tendon, TB-500 for systemic"),
        ("Ipamorelin", "CJC-1295", .synergy, "Amplified GH pulse  -  standard combination for recovery and body composition"),
        ("Creatine", "Electrolytes", .synergy, "Enhanced cellular hydration and performance together"),
        ("Omega-3", "Curcumin", .synergy, "Dual anti-inflammatory pathways for joint and systemic inflammation"),
        ("NAC", "Glutathione", .synergy, "NAC is a precursor to glutathione  -  redundant but complementary support"),
        ("Probiotics", "Berberine", .timing, "Berberine is antimicrobial  -  space 2h from probiotics"),
        ("Collagen", "Vitamin C", .synergy, "Vitamin C is required for collagen synthesis  -  always pair"),
        ("Tongkat Ali", "Fadogia Agrestis", .synergy, "Complementary testosterone support via different mechanisms"),
        ("Melatonin", "Magnesium", .synergy, "Combined sleep support  -  melatonin for onset, magnesium for quality"),
    ]

    static func getInteractions(for itemName: String, inProtocol protocolNames: [String]) -> [Interaction] {
        var results: [Interaction] = []
        let name = itemName.lowercased()

        for pair in interactionPairs {
            let aLower = pair.a.lowercased()
            let bLower = pair.b.lowercased()

            if aLower == name && protocolNames.contains(where: { $0.lowercased() == bLower }) {
                results.append(Interaction(itemName: pair.a, otherName: pair.b, kind: pair.kind, note: pair.note))
            } else if bLower == name && protocolNames.contains(where: { $0.lowercased() == aLower }) {
                results.append(Interaction(itemName: pair.b, otherName: pair.a, kind: pair.kind, note: pair.note))
            }
        }
        return results
    }

    static func getAllInteractions(forProtocol names: [String]) -> [Interaction] {
        var results: [Interaction] = []
        let lowerNames = names.map { $0.lowercased() }

        for pair in interactionPairs {
            let aLower = pair.a.lowercased()
            let bLower = pair.b.lowercased()
            if lowerNames.contains(aLower) && lowerNames.contains(bLower) {
                results.append(Interaction(itemName: pair.a, otherName: pair.b, kind: pair.kind, note: pair.note))
            }
        }
        return results
    }

    static func getTimingOptimizations(forProtocol names: [String]) -> [String] {
        let interactions = getAllInteractions(forProtocol: names)
        return interactions
            .filter { $0.kind == .timing || $0.kind == .conflict }
            .map { $0.note }
    }

    static func getStackSuggestions(forProtocol names: [String]) -> [String] {
        var suggestions: [String] = []
        let lowerNames = names.map { $0.lowercased() }

        if lowerNames.contains("vitamin d3") && !lowerNames.contains("vitamin k2") {
            suggestions.append("You take D3  -  consider adding K2 to direct calcium to bones")
        }
        if lowerNames.contains("collagen") && !lowerNames.contains("vitamin c") {
            suggestions.append("Collagen needs Vitamin C for synthesis  -  consider adding it")
        }
        if lowerNames.contains("iron") && !lowerNames.contains("vitamin c") {
            suggestions.append("Pair Iron with Vitamin C for 3x better absorption")
        }
        if lowerNames.contains("zinc") && !lowerNames.contains(where: { $0.contains("copper") }) {
            suggestions.append("Long-term zinc can deplete copper  -  consider a copper supplement")
        }
        if lowerNames.contains("ipamorelin") && !lowerNames.contains("cjc-1295") {
            suggestions.append("Ipamorelin works best paired with CJC-1295 for amplified GH release")
        }
        if lowerNames.contains("creatine") && !lowerNames.contains("electrolytes") {
            suggestions.append("Add electrolytes with creatine for better cellular hydration")
        }
        return suggestions
    }

    // MARK: - Meal Intelligence

    private static let mealEstimates: [(keywords: [String], info: MealInsight)] = [
        (["yogurt", "berries"], MealInsight(name: "Yogurt & Berries", estimatedCalories: 280, estimatedProtein: 15, estimatedCarbs: 35, estimatedFat: 8, emoji: "fork.knife", supplementNote: "Good with probiotics  -  dairy supports colonization")),
        (["eggs", "toast"], MealInsight(name: "Eggs & Toast", estimatedCalories: 380, estimatedProtein: 22, estimatedCarbs: 30, estimatedFat: 18, emoji: "cup.and.saucer.fill", supplementNote: "Fat content helps absorb D3, K2, and Omega-3")),
        (["chicken", "rice"], MealInsight(name: "Chicken & Rice", estimatedCalories: 520, estimatedProtein: 40, estimatedCarbs: 55, estimatedFat: 12, emoji: "fork.knife", supplementNote: "High protein meal  -  good time for creatine")),
        (["salad"], MealInsight(name: "Salad", estimatedCalories: 320, estimatedProtein: 12, estimatedCarbs: 20, estimatedFat: 22, emoji: "leaf.fill", supplementNote: "If dressing has fat, good time for fat-soluble vitamins")),
        (["protein shake", "shake", "whey"], MealInsight(name: "Protein Shake", estimatedCalories: 250, estimatedProtein: 30, estimatedCarbs: 15, estimatedFat: 5, emoji: "mug.fill", supplementNote: "Add creatine and collagen to your shake for convenience")),
        (["steak", "beef"], MealInsight(name: "Steak", estimatedCalories: 580, estimatedProtein: 50, estimatedCarbs: 0, estimatedFat: 38, emoji: "fork.knife", supplementNote: "Rich in iron, B12, zinc, and creatine naturally")),
        (["salmon", "fish"], MealInsight(name: "Salmon", estimatedCalories: 450, estimatedProtein: 38, estimatedCarbs: 0, estimatedFat: 28, emoji: "drop.fill", supplementNote: "Natural omega-3 source  -  may reduce fish oil need today")),
        (["oatmeal", "oats"], MealInsight(name: "Oatmeal", estimatedCalories: 310, estimatedProtein: 10, estimatedCarbs: 50, estimatedFat: 8, emoji: "cup.and.saucer", supplementNote: "Fiber may reduce supplement absorption  -  space iron/zinc 1h")),
        (["smoothie"], MealInsight(name: "Smoothie", estimatedCalories: 350, estimatedProtein: 20, estimatedCarbs: 45, estimatedFat: 10, emoji: "mug.fill", supplementNote: "Easy to add collagen, greens, and creatine")),
        (["pizza"], MealInsight(name: "Pizza", estimatedCalories: 600, estimatedProtein: 22, estimatedCarbs: 65, estimatedFat: 28, emoji: "fork.knife", supplementNote: "High-fat meal  -  fat-soluble vitamins absorb well here")),
    ]

    static func estimateMeal(_ description: String) -> MealInsight? {
        let lower = description.lowercased()
        return mealEstimates.first(where: { pair in
            pair.keywords.contains(where: { lower.contains($0) })
        })?.info
    }
}
