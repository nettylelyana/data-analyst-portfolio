WITH unpivoted_data AS (

    SELECT
        symbol,
        account,
        type,
        2020 AS year,
        "2020" AS value
    FROM combined_financial_data_idx

    UNION ALL

    SELECT
        symbol,
        account,
        type,
        2021 AS year,
        "2021" AS value
    FROM combined_financial_data_idx

    UNION ALL

    SELECT
        symbol,
        account,
        type,
        2022 AS year,
        "2022" AS value
    FROM combined_financial_data_idx

    UNION ALL

    SELECT
        symbol,
        account,
        type,
        2023 AS year,
        "2023" AS value
    FROM combined_financial_data_idx
),

selected_accounts AS (

    SELECT *
    FROM unpivoted_data
    WHERE symbol IN ('ICBP', 'INDF', 'MYOR', 'UNVR')
      AND account IN (
          'Total Revenue',
          'Gross Profit',
          'EBITDA',
          'EBIT',
          'Operating Income',
          'Net Income',
          'Total Assets',
          'Common Stock Equity',
          'Current Assets',
          'Current Liabilities',
          'Total Debt',
          'Cash Flowsfromusedin Operating Activities Direct',
          'Investing Cash Flow',
          'Financing Cash Flow',
          'Free Cash Flow',
          'Capital Expenditure'
      )
)

SELECT
    symbol,
    year,

    MAX(CASE WHEN account = 'Total Revenue'
        THEN value END) AS revenue,

    MAX(CASE WHEN account = 'Gross Profit'
        THEN value END) AS gross_profit,

    MAX(CASE WHEN account = 'EBITDA'
        THEN value END) AS ebitda,

    MAX(CASE WHEN account = 'EBIT'
        THEN value END) AS ebit,

    MAX(CASE WHEN account = 'Operating Income'
        THEN value END) AS operating_income,

    MAX(CASE WHEN account = 'Net Income'
        THEN value END) AS net_income,

    MAX(CASE WHEN account = 'Total Assets'
        THEN value END) AS total_assets,

    MAX(CASE WHEN account = 'Common Stock Equity'
        THEN value END) AS equity,

    MAX(CASE WHEN account = 'Current Assets'
        THEN value END) AS current_assets,

    MAX(CASE WHEN account = 'Current Liabilities'
        THEN value END) AS current_liabilities,

    MAX(CASE WHEN account = 'Total Debt'
        THEN value END) AS total_debt,

    MAX(CASE WHEN account = 'Cash Flowsfromusedin Operating Activities Direct'
        THEN value END) AS operating_cash_flow,

    MAX(CASE WHEN account = 'Investing Cash Flow'
        THEN value END) AS investing_cash_flow,

    MAX(CASE WHEN account = 'Financing Cash Flow'
        THEN value END) AS financing_cash_flow,

    MAX(CASE WHEN account = 'Free Cash Flow'
        THEN value END) AS free_cash_flow,

    MAX(CASE WHEN account = 'Capital Expenditure'
        THEN value END) AS capital_expenditure

FROM selected_accounts
GROUP BY symbol, year
ORDER BY symbol, year;

