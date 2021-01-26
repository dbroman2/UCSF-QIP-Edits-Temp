/*
MEASURE W34-CH: WELL-CHILD VISITS IN THE THIRD, FOURTH, FIFTH AND SIXTH YEARS OF LIFE
QIP PC
Measure W34-CH: WELL-CHILD VISITS IN THE THIRD, FOURTH, FIFTH AND SIXTH YEARS OF LIFE
Author: Matthew Crase
Organization: UC Davis
Created: 2020-11-10
Description: Percentage of children ages 3 to 6 who had one or more well-child visits 
				with a primary care practitioner (PCP) during the measurement year.
*/

Create PROCEDURE [dbo].[measure_nqf_1516_hedis_w34_2020]
    @start_dt DATE
    , @end_dt DATE
    , @well_care_visit_vs VARCHAR(255)
	, @pcp_vs VARCHAR(255)
    , @hospice_vs VARCHAR(255)
	, @telehealth_modifier_vs VARCHAR(255) 
    , @telehealth_pos_vs VARCHAR(255) 
	, @program_name VARCHAR(255)

AS

/*
DECLARE
    @start_dt DATE = '2020-01-01'
    , @end_dt DATE = '2020-12-31'
    , @well_care_visit_vs VARCHAR(255) = 'HEDIS 2020 - Measure W34: Well-Child Visits in the Third, Fourth, Fifth and Sixth Years of Life - Well-Care'
	, @pcp_vs VARCHAR(255) = 'UCHDW - Local Value Sets - MSSP Primary Care Physician'
	, @hospice_vs VARCHAR(255) = 'UCD - Local Value Sets - Hospice'
	, @telehealth_modifier_vs VARCHAR(255) = 'HEDIS 2020 - Measure CDC: Comprehensive Diabetes Care - Telehealth Modifier'
    , @telehealth_pos_vs VARCHAR(255) = 'HEDIS 2020 - Measure CDC: Comprehensive Diabetes Care - Telehealth POS'
	, @program_name VARCHAR(255) = 'QIP'


-- Continuous Enrollment During Measurment Year
/*
No more than one gap in enrollment of up to 45 days during the continuous enrollment period. 
To determine continuous enrollment for a beneficiary for whom enrollment is verified monthly, 
the child may not have more than a 1-month gap in coverage 
(i.e., a child whose coverage lapses for 2 months [60 days] is not considered continuously enrolled).
*/

DROP TABLE IF EXISTS #cohort
SELECT mrn
INTO #cohort
FROM QIP.dbo.cohort_QIP
WHERE continuous_enrollment = 1
*/

/*
Children who are greater or equal to 3 years old or less than or equal to 6 years old by December 31st of the measurement year.
*/

DROP TABLE IF EXISTS #age

SELECT person_id
		, c.mrn
		, birth_date
		, narrative_text = CONCAT('Age ', cast(QualityMeasures.dbo.qm_age(person.birth_date, @end_dt) as VARCHAR), ' as of December 31 of the measurement year.')
INTO #age
FROM #cohort c
    JOIN OMOP_EZ.dbo.person
        ON person.mrn = c.mrn
WHERE --between 3 AND 6 at end of reporting period
            @end_dt >= DATEADD(YEAR, 3, person.birth_date)
            AND @end_dt < DATEADD(YEAR, 7, person.birth_date)


-- select * from #age

/*
## Visits With Child Well Care Procedures
*/

DROP TABLE IF EXISTS #visit_proc_diag_all

	SELECT #age.person_id
			, po.visit_occurrence_id
			, narrative_text = CONCAT(LEFT(po.procedure_text, 32)
							, CASE WHEN LEN(po.procedure_text) > 32 THEN '..' END
							, procedure_code_modifier_text
							, procedure_code_modifier2_text
							, procedure_code_modifier3_text
							, ' on ', FORMAT(po.procedure_date, 'M/d/yy')
							, ' (', po.procedure_vocabulary_id, ' ', po.procedure_code, procedure_code_modifier, procedure_code_modifier2, procedure_code_modifier3
							, ', ', procedure_priority
							, ', ', po.procedure_source, ', ', procedure_source_type
							, ').'
						)
			, po.procedure_date

into   #visit_proc_diag_all

FROM #age
    JOIN OMOP_EZ.dbo.procedure_occurrence po
        ON po.person_id = #age.person_id
		AND po.procedure_date BETWEEN @start_dt AND @end_dt
   
    JOIN TerminologyServices.dbo.ValueSet vs
        ON vs.ValueSetName = @well_care_visit_vs
            AND vs.Vocabulary = po.procedure_vocabulary_id
            AND vs.Code = po.procedure_code
	  --Limit to PCP visits
    JOIN OMOP_EZ.dbo.[provider] p
        ON p.provider_id = po.provider_id

    LEFT JOIN TerminologyServices.dbo.ValueSet pcp_vs
        ON pcp_vs.ValueSetName = @pcp_vs
            AND pcp_vs.Code = p.cms_specialty_code

	LEFT JOIN OMOP_EZ.[dbo].[visit_provider_role] r
		on r.visit_occurrence_id = po.visit_occurrence_id
		AND r.provider_role = 'Cosigning Provider'

	LEFT  JOIN OMOP_EZ.dbo.[provider] p2
        ON p2.provider_id = r.provider_id

	LEFT JOIN TerminologyServices.dbo.ValueSet pcp_vs2
        ON pcp_vs2.ValueSetName = @pcp_vs
            AND pcp_vs2.Code = p2.cms_specialty_code

	WHERE	(pcp_vs.Code = p.cms_specialty_code)
			OR
			(pcp_vs2.Code = p2.cms_specialty_code)

UNION ALL 
--Diagnosis

SELECT #age.person_id, co.visit_occurrence_id,

     narrative_text = CONCAT(
        condition_text, ' on ', FORMAT(condition_start_date, 'M/d/yy')
        , ' (', condition_vocabulary_id, ' ', condition_code
        , ', ', condition_source, ', ', condition_priority
        , ').'
        )
		,co.condition_start_date

FROM #age
    JOIN OMOP_EZ.dbo.condition_occurrence co
        ON co.person_id = #age.person_id
		AND co.condition_start_date BETWEEN @start_dt AND @end_dt
    JOIN TerminologyServices.dbo.ValueSet vs
        ON vs.ValueSetName = @well_care_visit_vs
            AND vs.Vocabulary = co.condition_vocabulary_id
            AND vs.Code = co.condition_code
	--Limit to PCP visits
	JOIN OMOP_EZ.dbo.[provider] p
        ON p.provider_id = co.provider_id

    LEFT JOIN TerminologyServices.dbo.ValueSet pcp_vs
        ON pcp_vs.ValueSetName = @pcp_vs
            AND pcp_vs.Code = p.cms_specialty_code

	LEFT JOIN OMOP_EZ.[dbo].[visit_provider_role] r
		on r.visit_occurrence_id = co.visit_occurrence_id
		AND r.provider_role = 'Cosigning Provider'

	LEFT  JOIN OMOP_EZ.dbo.[provider] p2
        ON p2.provider_id = r.provider_id

	LEFT JOIN TerminologyServices.dbo.ValueSet pcp_vs2
        ON pcp_vs2.ValueSetName = @pcp_vs
            AND pcp_vs2.Code = p2.cms_specialty_code

	WHERE	(pcp_vs.Code = p.cms_specialty_code)
			OR
			(pcp_vs2.Code = p2.cms_specialty_code)

-- Do not count visits billed with a telehealth modifier (Telehealth Modifier Value Set) or billed 
-- with a telehealth POS code (Telehealth POS Value Set).

DROP TABLE IF EXISTS #telehealth

SELECT DISTINCT  v.visit_occurrence_id

INTO #telehealth

FROM #visit_proc_diag_all v
    JOIN OMOP_EZ.dbo.procedure_occurrence po
        ON po.visit_occurrence_id = v.visit_occurrence_id
	JOIN OMOP_EZ.dbo.visit_occurrence AS vo
        ON vo.visit_occurrence_id = po.visit_occurrence_id
    JOIN OMOP_EZ.dbo.care_site AS cs
        ON cs.care_site_id = vo.care_site_id
    JOIN TerminologyServices.dbo.ValueSet AS vs
        ON vs.ValueSetName IN (@telehealth_modifier_vs, @telehealth_pos_vs)
            AND (
                (Vocabulary = 'CPT4' AND vs.Code IN (po.procedure_code_modifier, po.procedure_code_modifier2, po.procedure_code_modifier3))
                OR (Vocabulary = 'CMS Place of Service' AND vs.Code = cs.place_of_service_code)
                )

--At least one well-child visit (Well-Care Value Set) with a PCP during the measurement year.

DROP TABLE IF EXISTS #visit

SELECT 
		c.person_id
		, c.procedure_date
		, c.visit_occurrence_id
		, c.narrative_text

INTO	#visit
FROM 
( 

SELECT 
		v.person_id
		, v.procedure_date
		, v.visit_occurrence_id
		, v.narrative_text
		, ROW_NUMBER() OVER(PARTITION BY v.person_id ORDER BY v.procedure_date ASC) vis_row_number

FROM #visit_proc_diag_all v
	LEFT JOIN #telehealth t on v.visit_occurrence_id = t.visit_occurrence_id
 
WHERE t.visit_occurrence_id is null
	
)C
	WHERE vis_row_number=1

-- select * from #visit

/*
Exclusion - Hospice
Keep first record.
*/

DROP TABLE IF EXISTS #exclusion_hospice;

WITH exclusion AS (

SELECT
    c.person_id
    , vo.visit_number action_visit_number
    , po.procedure_date exclusion_date
    , CONCAT(
        po.procedure_text, ' on ', FORMAT(po.procedure_date, 'M/d/yy')
        , ' (' + po.procedure_vocabulary_id, ' ', po.procedure_code
        , ', ', po.procedure_source, ' ', po.procedure_source_type, ').'
        ) narrative_text
FROM #age c
    JOIN OMOP_EZ.dbo.procedure_occurrence po
        ON po.person_id = c.person_id
            AND po.procedure_date BETWEEN @start_dt AND @end_dt
    JOIN TerminologyServices.dbo.ValueSet vs
        ON vs.ValueSetName = @hospice_vs
            AND vs.Vocabulary = po.procedure_vocabulary_id
            AND vs.Code = po.procedure_code
    LEFT JOIN OMOP_EZ.dbo.visit_occurrence vo
        ON vo.visit_occurrence_id = po.visit_occurrence_id
        AND vo.visit_occurrence_id <> -1

UNION

SELECT
    c.person_id
    , vo.visit_number action_visit_number
    , co.condition_start_date exclusion_date
    , CONCAT(
        co.condition_text, ' on ', FORMAT(co.condition_start_date, 'M/d/yy')
        , ' (' + co.condition_vocabulary_id, ' ', co.condition_code
        , ', ', co.condition_source, ' ', co.condition_type, ').'
        ) narrative_text
FROM #age c
    JOIN OMOP_EZ.dbo.condition_occurrence co
        ON co.person_id = c.person_id
            AND co.condition_start_date BETWEEN @start_dt AND @end_dt
    JOIN TerminologyServices.dbo.ValueSet vs
        ON vs.ValueSetName = @hospice_vs
            AND vs.Vocabulary = co.condition_vocabulary_id
            AND vs.Code = co.condition_code
    LEFT JOIN OMOP_EZ.dbo.visit_occurrence vo
        ON vo.visit_occurrence_id = co.visit_occurrence_id
        AND vo.visit_occurrence_id <> -1

UNION

SELECT 
    c.person_id
    , vo.visit_number action_visit_number
    , vo.visit_end_datetime exclusion_date
    , CONCAT(
        vo.visit_type, ' discharge ', FORMAT(vo.visit_end_datetime, 'M/d/yy')
        , ' (UB04 discharge disposition: ' , vo.ub04_discharge_disposition_code
        , ' ' , vo.ub04_discharge_disposition, ').'        
        ) narrative_text
FROM #age c
    JOIN OMOP_EZ.dbo.visit_occurrence vo
        ON vo.person_id = c.person_id
        AND vo.ub04_discharge_disposition_code IN ('50', '51') 
        AND CAST(vo.visit_end_datetime AS DATE) BETWEEN @start_dt AND @end_dt
        AND vo.visit_occurrence_id <> -1
)
, numbered AS (

SELECT *, ROW_NUMBER() OVER(PARTITION BY person_id ORDER BY exclusion_date ASC) exclusion_row_number
FROM exclusion

)
SELECT *
INTO #exclusion_hospice
FROM numbered
WHERE exclusion_row_number = 1
;

/*
## Show Results
*/

SELECT
     NULL rate_name 
    , #cohort.mrn
    , NULL index_visit_number
    , NULL action_visit_number
    , CONCAT(COALESCE(#age.narrative_text, 'Age does not qualify.')
        , ' ' + COALESCE(#visit.narrative_text, 'No Child Well Care Visits.')
        , ' ' + COALESCE(#exclusion_hospice.narrative_text, 'No Hospice Exclusion.')
        ) narrative_text 
	, CASE 
        WHEN #age.person_id IS NULL THEN 'Initial Population'
        WHEN @program_name = 'QIP' AND EXISTS (SELECT * FROM OMOP_EZ.dbo.person WHERE mrn = #cohort.mrn AND death_date BETWEEN @start_dt AND @end_dt) THEN 'Deceased Patient'  --QIP FILTER - Categorize deceased patients
        WHEN #exclusion_hospice.person_id IS NOT NULL	THEN 'Denominator Exclusion'
        WHEN #visit.person_id IS NOT NULL				THEN 'Numerator'        
        ELSE 'Denominator' 
		END reporting_category 
FROM #cohort
	LEFT JOIN #age
		ON #cohort.mrn = #age.mrn
    LEFT JOIN #visit
        ON #visit.person_id = #age.person_id
	LEFT JOIN #exclusion_hospice
        ON #exclusion_hospice.person_id = #age.person_id

