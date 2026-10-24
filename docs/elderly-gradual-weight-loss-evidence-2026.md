# Older hypertension/obesity: gentle first week and measured tolerance

## 2026-10-24 change request
An approximately 178 cm, 100 kg person reports feeling very hungry after starting the plan. Height and weight alone do **not** establish daily calorie requirements: age, sex, physical activity, medications, kidney function and prior intake materially change clinical decisions. The app already has age, sex and estimated activity in the profile; it must not substitute a hard-coded calorie number for the 100-kg example.

### Evidence and other apps

- ESPEN Clinical Nutrition and Hydration in Geriatrics (2022), R55–R57: explicitly weigh risks and benefits of weight loss in older people, use only moderate caloric restriction and combine with feasible exercise to preserve muscle. https://www.clinicalnutritionjournal.com/article/S0261-5614%2822%2900034-6/fulltext
- Beijing Hospital / National Center for Gerontology **Expert Consensus on Management of Obesity in Older Adults (2026)**: first stratify function, muscle, comorbidities and age; pursue steady changes, not rapid weight loss, especially for frailty. https://pmc.ncbi.nlm.nih.gov/articles/PMC13535939/
- CDC Avoid getting over-hungry, and favor gradual sustainable changes: https://www.cdc.gov/healthy-weight-growth/losing-weight/keeping-it-off.html
- Mayo Clinic Diet uses habit phases. Its optional fast initial weight-loss phase **is not suitable to copy verbatim** for frail/high-risk elderly people: https://diet.mayoclinic.org/us/weight-loss-programs/about-the-mayo-clinic-diet/
- Noom uses personalized calorie target ranges and weight-trend feedback, not a universal single target: https://www.noom.com/support/faqs/using-the-app/logging-and-tracking/biometrics/2025/10/how-noom-sets-your-weight-loss-zone-and-tracks-your-progress/

### Policy as implemented (product guardrail, **not a guideline-prescribed exact schedule**)

1. New users start a 7-day adaptation week at approximately **2% below estimated maintenance**, with a small recipe-validation range, and never exceed estimated maintenance. The nutritional catalogue still requires at least 1800 kcal/day, adequate protein, vegetables, fruit, dairy, and sodium/oil limits. If the energy model cannot support a safely reduced target in the catalogue, deny auto generation and recommend individualized professional guidance.
2. Day-page one-tap report: comfortable, often hungry, or too hungry / unwell. Reports stored in the existing profile-isolated local planner state. **No report is not permission to restrict calories.**
3. Only if at least three days in the prior 7-day window explicitly report comfortable (and no hungry/unwell reports) may the next week's deficit deepen by **one** step: 2% → 5% → 10%. Automated planned restriction is capped at 350 kcal/day. A hungry report holds steady. Too hungry/unwell resets to the gentlest stage; warn not to endure dizziness or weakness and seek medical assessment.
4. There is no irreversible countdown; missed reporting keeps the same stage, and changes do not silently replace existing plans or backfill food diary records. Historical adjustments preserve the old weekly kcal contract. Change of feedback during AI generation rejects the stale result.
5. This is a deliberately cautious, testable policy hypothesis for this app. It has **not** been clinically validated as a treatment or as an optimal percentage schedule. Clinicians should review it before using with high-risk patients. Severe symptoms, antihypertensives, diabetes medication, sarcopenia and kidney disease require individualized assessment; do not advise changing medications.

### Not implemented
- No unsupervised diuretic/antihypertensive adjustments.
- No assumption that BMI distinguishes adiposity from sarcopenia.
- No automatic treatment decisions based solely on hunger or scale measurements.
- No unvalidated nutrient numbers.
