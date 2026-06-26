import Foundation

struct MedicationInfo {
    let name: String
    let aliases: [String]
    let category: String
    let defaultDose: String
    let benefit: String
    let mechanism: String
    let pros: [String]
    let cons: [String]
}

enum MedicationKnowledge {

    static let database: [MedicationInfo] = [
        MedicationInfo(
            name: "Metformin", aliases: ["glucophage"],
            category: "medication", defaultDose: "500 mg",
            benefit: "Blood sugar control, potential longevity and anti-cancer benefits",
            mechanism: "Activates AMPK, reduces hepatic glucose production, improves insulin sensitivity",
            pros: ["Reduces blood sugar and A1C effectively", "Potential anti-aging and longevity benefits (TAME trial)", "May reduce cancer risk", "Promotes modest weight loss", "Improves insulin sensitivity", "Inexpensive and well-studied for decades", "May reduce cardiovascular events"],
            cons: ["GI side effects: nausea, diarrhea, bloating (very common initially)", "Depletes B12 — must supplement", "Lactic acidosis (rare but serious)", "Metallic taste in mouth", "May reduce muscle gains from exercise", "Not for severe kidney disease", "Can cause hypoglycemia when combined with other diabetes meds"]
        ),
        MedicationInfo(
            name: "Gabapentin", aliases: ["neurontin"],
            category: "medication", defaultDose: "300 mg",
            benefit: "Nerve pain relief, anxiety reduction, sleep improvement",
            mechanism: "Binds alpha-2-delta subunit of voltage-gated calcium channels, reducing excitatory neurotransmission",
            pros: ["Effective for neuropathic pain", "Reduces anxiety (off-label)", "Improves sleep quality", "Non-addictive compared to opioids/benzos", "Helps with restless leg syndrome", "Can reduce alcohol withdrawal symptoms"],
            cons: ["Drowsiness and sedation", "Dizziness and coordination problems", "Weight gain", "Brain fog and cognitive impairment", "Physical dependence with long-term use", "Withdrawal symptoms if stopped abruptly", "Swelling in extremities (edema)", "Mood changes and depression in some"]
        ),
        MedicationInfo(
            name: "Levothyroxine", aliases: ["synthroid", "t4", "thyroid"],
            category: "medication", defaultDose: "50 mcg",
            benefit: "Thyroid hormone replacement for hypothyroidism",
            mechanism: "Synthetic T4 that converts to active T3, restoring normal metabolic rate",
            pros: ["Restores normal energy levels", "Reverses weight gain from hypothyroidism", "Improves mood and mental clarity", "Prevents complications of untreated hypothyroidism", "Inexpensive and well-established", "Once-daily dosing"],
            cons: ["Requires lifelong use", "Takes weeks to reach steady state", "Must be taken on empty stomach (strict timing)", "Over-replacement causes anxiety, palpitations, bone loss", "Many drug interactions", "Requires regular blood monitoring", "Hair loss during dose adjustments", "Sensitive to brand switches"]
        ),
        MedicationInfo(
            name: "Adderall", aliases: ["amphetamine", "dextroamphetamine", "adderall xr"],
            category: "medication", defaultDose: "20 mg",
            benefit: "Improves focus, attention, and executive function in ADHD",
            mechanism: "Increases dopamine and norepinephrine release in prefrontal cortex",
            pros: ["Dramatically improves focus and productivity", "Reduces ADHD symptoms effectively", "Fast onset of action", "Improves working memory", "Can be life-changing for diagnosed ADHD"],
            cons: ["High addiction and abuse potential (Schedule II)", "Appetite suppression and weight loss", "Insomnia if taken too late", "Increased heart rate and blood pressure", "Anxiety, irritability, and mood swings", "Crash/rebound when wearing off", "Tolerance develops over time", "Cardiovascular risks with long-term use", "Can worsen psychosis or mania"]
        ),
        MedicationInfo(
            name: "Modafinil", aliases: ["provigil"],
            category: "medication", defaultDose: "200 mg",
            benefit: "Wakefulness promotion, cognitive enhancement, focus",
            mechanism: "Inhibits dopamine reuptake and modulates histamine/orexin systems",
            pros: ["Promotes wakefulness without jitteriness", "Lower abuse potential than amphetamines", "Enhances cognitive performance", "Long duration (12-15 hours)", "Improves motivation and focus", "Fewer cardiovascular side effects than stimulants"],
            cons: ["Headaches (most common side effect)", "Insomnia if taken too late (long half-life)", "Anxiety and irritability", "Rare but serious: Stevens-Johnson Syndrome (skin reaction)", "Can reduce effectiveness of hormonal birth control", "Nausea and appetite loss", "Tolerance can develop", "May cause dehydration"]
        ),
        MedicationInfo(
            name: "Finasteride", aliases: ["propecia", "proscar"],
            category: "medication", defaultDose: "1 mg",
            benefit: "Prevents hair loss by blocking DHT conversion",
            mechanism: "Inhibits 5-alpha reductase type II, reducing DHT by ~70%",
            pros: ["Stops hair loss in 90% of men", "Regrows hair in 65% of men", "Once-daily oral pill (convenient)", "Reduces prostate size (BPH)", "Well-studied over 20+ years", "Inexpensive (generic available)"],
            cons: ["Sexual side effects: reduced libido, erectile dysfunction (2-4%)", "Post-finasteride syndrome (controversial but reported)", "Depression and brain fog in some users", "Gynecomastia (breast tissue growth) rare", "Must be taken indefinitely for hair", "Affects PSA test results", "Not for use by women of childbearing age", "Semen volume reduction"]
        ),
        MedicationInfo(
            name: "Minoxidil", aliases: ["rogaine"],
            category: "medication", defaultDose: "5%",
            benefit: "Stimulates hair regrowth and prevents further loss",
            mechanism: "Vasodilator that increases blood flow to hair follicles and extends growth phase",
            pros: ["Proven to regrow hair", "Available over-the-counter", "Works for men and women", "Can be combined with finasteride", "Topical — fewer systemic side effects", "Relatively inexpensive"],
            cons: ["Initial shedding phase (alarming but temporary)", "Must be applied daily forever (loss resumes if stopped)", "Scalp irritation and dryness", "Unwanted facial hair growth (women)", "Fluid retention possible", "Heart palpitations (rare, oral form)", "Results take 4-6 months to see", "Can be messy to apply (liquid form)"]
        ),
        MedicationInfo(
            name: "Testosterone", aliases: ["trt", "testosterone cypionate", "test cyp", "testosterone enanthate"],
            category: "medication", defaultDose: "100 mg/week",
            benefit: "Hormone replacement for low T: energy, muscle, libido, mood",
            mechanism: "Exogenous testosterone restoring physiological androgen levels",
            pros: ["Restores energy and eliminates fatigue", "Significantly improves libido", "Increases muscle mass and strength", "Improves mood and reduces depression", "Enhances bone density", "Improves cognitive function", "Reduces body fat"],
            cons: ["Suppresses natural testosterone production (may be permanent)", "Requires lifelong commitment once started", "Polycythemia (elevated red blood cells) — needs monitoring", "Acne and oily skin", "Hair loss acceleration in genetically prone", "Testicular atrophy", "Fertility suppression (reduced/zero sperm)", "Mood swings if levels fluctuate", "Cardiovascular risk debate", "Requires regular blood work monitoring", "Estrogen conversion may require AI"]
        ),
        MedicationInfo(
            name: "Rapamycin", aliases: ["sirolimus"],
            category: "medication", defaultDose: "5 mg/week",
            benefit: "mTOR inhibition for potential longevity and anti-aging benefits",
            mechanism: "Inhibits mTOR Complex 1, promoting autophagy and reducing cellular senescence",
            pros: ["Most promising longevity drug in animal studies", "Promotes autophagy (cellular cleanup)", "May reduce cancer risk", "Improves immune function at low doses", "Potential cardiovascular benefits", "Reduces cellular senescence"],
            cons: ["Immunosuppression at higher doses", "Mouth sores/ulcers (common)", "Impaired wound healing", "Elevated cholesterol and triglycerides", "May increase diabetes risk at high doses", "Limited human longevity data", "Requires medical supervision", "Potential for serious infections"]
        ),
        MedicationInfo(
            name: "Low-Dose Naltrexone", aliases: ["ldn", "naltrexone"],
            category: "medication", defaultDose: "4.5 mg",
            benefit: "Immune modulation, pain reduction, anti-inflammatory",
            mechanism: "Brief opioid receptor blockade triggers upregulation of endorphins and enkephalins",
            pros: ["Reduces autoimmune symptoms", "Lowers systemic inflammation", "Improves chronic pain conditions", "May help fibromyalgia and Crohn's", "Very few side effects at low dose", "Inexpensive", "May improve mood via endorphin upregulation"],
            cons: ["Vivid dreams or nightmares (common initially)", "Sleep disturbance first 1-2 weeks", "Nausea initially", "Cannot take with opioid medications", "Off-label use — limited large trials", "Requires compounding pharmacy", "May temporarily worsen symptoms before improving"]
        ),
        MedicationInfo(
            name: "Ozempic", aliases: ["semaglutide", "wegovy"],
            category: "medication", defaultDose: "0.5 mg/week",
            benefit: "Weight loss and blood sugar control via GLP-1 receptor agonism",
            mechanism: "GLP-1 receptor agonist that slows gastric emptying, reduces appetite, and improves insulin secretion",
            pros: ["Significant weight loss (15-20% body weight)", "Reduces cardiovascular risk", "Improves blood sugar control", "Reduces food noise and cravings", "Once-weekly injection", "FDA-approved with extensive safety data"],
            cons: ["Severe nausea especially during dose escalation", "Vomiting, diarrhea, constipation", "Risk of pancreatitis", "Gallbladder problems and gallstones", "Thyroid C-cell tumor concern (animal studies)", "Muscle loss without resistance training", "'Ozempic face' (facial volume loss)", "Very expensive ($1000+/month without insurance)", "Weight regain when discontinued"]
        ),
        MedicationInfo(
            name: "Lisinopril", aliases: ["ace inhibitor", "prinivil", "zestril"],
            category: "medication", defaultDose: "10 mg",
            benefit: "Blood pressure reduction, heart and kidney protection",
            mechanism: "ACE inhibitor that blocks angiotensin II formation, reducing vasoconstriction",
            pros: ["Effectively lowers blood pressure", "Protects kidneys (especially in diabetes)", "Reduces heart failure progression", "Cardioprotective after heart attack", "Inexpensive generic", "Once-daily dosing"],
            cons: ["Persistent dry cough (10-20% of users)", "Dizziness from blood pressure drops", "Hyperkalemia (high potassium)", "Angioedema (rare but serious swelling)", "Can worsen kidney function initially", "Not safe during pregnancy", "May cause fatigue"]
        ),
        MedicationInfo(
            name: "Atorvastatin", aliases: ["lipitor", "statin"],
            category: "medication", defaultDose: "20 mg",
            benefit: "Lowers LDL cholesterol and reduces cardiovascular events",
            mechanism: "HMG-CoA reductase inhibitor that blocks cholesterol synthesis in the liver",
            pros: ["Significantly reduces LDL cholesterol (30-50%)", "Proven to reduce heart attack and stroke risk", "Anti-inflammatory effects beyond cholesterol", "Reduces cardiovascular mortality", "Inexpensive generic", "Well-studied over decades"],
            cons: ["Muscle pain and weakness (myalgia) in 5-10%", "Depletes CoQ10 — supplement recommended", "Liver enzyme elevation (monitor)", "Increased diabetes risk", "Memory issues and brain fog reported", "Rare: rhabdomyolysis (muscle breakdown)", "Fatigue and weakness", "GI upset"]
        ),
        MedicationInfo(
            name: "Tretinoin", aliases: ["retin-a", "retinoid", "retinoic acid"],
            category: "medication", defaultDose: "0.025%",
            benefit: "Gold standard for acne and anti-aging skin treatment",
            mechanism: "Vitamin A derivative that accelerates cell turnover and stimulates collagen",
            pros: ["Proven to reduce wrinkles and fine lines", "Treats and prevents acne", "Improves skin texture and tone", "Reduces hyperpigmentation", "Stimulates collagen production", "Decades of clinical evidence", "Prevents skin cancer (actinic keratoses)"],
            cons: ["Severe dryness and peeling (retinization period)", "Sun sensitivity — must use SPF daily", "Initial purge (acne worsens before improving)", "Skin irritation, burning, and redness", "Not safe during pregnancy", "Takes 3-6 months for results", "Cannot combine with certain actives (vitamin C, BHA at same time)"]
        ),
        MedicationInfo(
            name: "Accutane", aliases: ["isotretinoin"],
            category: "medication", defaultDose: "40 mg",
            benefit: "Eliminates severe cystic acne permanently in most cases",
            mechanism: "Reduces sebum production by up to 90%, shrinks oil glands permanently",
            pros: ["Cures severe acne permanently in 85% of cases", "Reduces scarring from active acne", "Results are often permanent after one course", "Dramatically improves quality of life", "Reduces oil production long-term"],
            cons: ["Extreme dryness (lips, skin, eyes)", "Birth defects — strict pregnancy prevention required (iPLEDGE)", "Depression and mood changes (debated but reported)", "Joint and muscle pain", "Elevated cholesterol and liver enzymes", "Dry eyes and night vision issues", "Hair thinning during treatment", "Monthly blood tests required", "Photosensitivity", "Inflammatory bowel disease concern (controversial)"]
        ),
        MedicationInfo(
            name: "Lexapro", aliases: ["escitalopram", "ssri"],
            category: "medication", defaultDose: "10 mg",
            benefit: "Treats depression and generalized anxiety disorder",
            mechanism: "Selective serotonin reuptake inhibitor (SSRI) increasing synaptic serotonin",
            pros: ["Effective for depression and anxiety", "Generally well-tolerated", "Once-daily dosing", "Fewer side effects than older antidepressants", "Helps with panic disorder", "Reduces OCD symptoms"],
            cons: ["Sexual dysfunction (reduced libido, anorgasmia) — very common", "Weight gain over time", "Emotional blunting or numbness", "Nausea and GI upset initially", "Withdrawal symptoms if stopped abruptly (brain zaps)", "Increased suicidality warning in young adults (first weeks)", "Insomnia or drowsiness", "Takes 4-6 weeks for full effect", "Serotonin syndrome risk with certain combos"]
        ),
        MedicationInfo(
            name: "Wellbutrin", aliases: ["bupropion"],
            category: "medication", defaultDose: "150 mg",
            benefit: "Antidepressant that also helps with focus and smoking cessation",
            mechanism: "Norepinephrine-dopamine reuptake inhibitor (NDRI)",
            pros: ["Does not cause sexual dysfunction (unlike SSRIs)", "May cause weight loss (appetite suppression)", "Improves focus and motivation", "Helps with smoking cessation", "Energizing rather than sedating", "Can augment SSRI therapy"],
            cons: ["Increased seizure risk (dose-dependent)", "Anxiety, agitation, and insomnia", "Headaches", "Dry mouth", "Cannot be used with eating disorders (seizure risk)", "May worsen anxiety in some people", "Insomnia if taken too late", "Irritability"]
        ),
        MedicationInfo(
            name: "Tadalafil", aliases: ["cialis"],
            category: "medication", defaultDose: "5 mg",
            benefit: "Erectile dysfunction treatment, also improves blood flow and prostate health",
            mechanism: "PDE5 inhibitor that enhances nitric oxide-mediated vasodilation",
            pros: ["Long duration (36 hours vs 4-6h for Viagra)", "Low-dose daily option available", "Improves erectile function significantly", "Treats BPH (enlarged prostate) symptoms", "May improve exercise capacity", "Possible cardiovascular benefits at low doses"],
            cons: ["Headaches (common)", "Facial flushing", "Back pain and muscle aches", "Nasal congestion", "Indigestion", "Cannot combine with nitrates (dangerous BP drop)", "Priapism (rare but emergency)", "Vision changes (rare)", "Hearing loss (very rare)"]
        ),
        MedicationInfo(
            name: "Clomiphene", aliases: ["clomid"],
            category: "medication", defaultDose: "25 mg",
            benefit: "Restores natural testosterone production, preserves fertility",
            mechanism: "Selective estrogen receptor modulator (SERM) that blocks hypothalamic estrogen feedback, increasing LH/FSH",
            pros: ["Increases testosterone while preserving fertility", "Oral medication (no injections)", "Alternative to TRT for younger men", "Increases LH and FSH naturally", "Reversible — can stop anytime", "Maintains testicular function and size"],
            cons: ["Visual disturbances (blurring, floaters)", "Mood swings and irritability", "Elevated estrogen possible", "Headaches", "Not as effective as TRT for symptom relief", "May not work in primary hypogonadism", "Hot flashes", "Gynecomastia possible"]
        ),
    ]

    static func find(_ name: String) -> MedicationInfo? {
        let lower = name.lowercased()
        return database.first { info in
            info.name.lowercased() == lower ||
            info.aliases.contains(where: { lower.contains($0) || $0.contains(lower) })
        }
    }

    static func fuzzyMatch(_ query: String) -> [MedicationInfo] {
        let lower = query.lowercased()
        return database.filter { info in
            info.name.lowercased().contains(lower) ||
            info.aliases.contains(where: { $0.contains(lower) || lower.contains($0) })
        }
    }
}
