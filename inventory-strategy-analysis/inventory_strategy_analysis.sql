-- =================================================================================
-- Total Revenue by Store and Product
-- =================================================================================
CREATE OR REPLACE VIEW vw_sales_performance
AS
	SELECT 
	 	sl.date,
	    st.store_id,
	    st.store_name,
	    p.product_id,
	    p.product_name,
	    p.product_category,
	    sl.units AS units_sold,
	    p.product_price,
	    sl.units::numeric * p.product_price AS revenue
	FROM sales sl
	JOIN products p 
		ON sl.product_id = p.product_id
	JOIN stores st 
		ON sl.store_id = st.store_id;

-- =================================================================================
-- Total Revenue by Product Name
-- =================================================================================
CREATE OR REPLACE VIEW vw_product_revenue
AS
	SELECT 
		product_name,
    	sum(revenue) AS revenue
   	FROM vw_sales_performance
  	GROUP BY product_name;

-- =================================================================================
-- Inventory Turnover by Store and Product
-- Beginning and ending inventory values are not available in the dataset. 
-- Turnover is therefore calculated using units sold relative to inventory quantity.
-- =================================================================================
CREATE OR REPLACE VIEW vw_inventory_turnover
AS
	WITH sales_cte 
	AS (
		SELECT 
			sales.store_id,
        	sales.product_id,
       		sum(sales.units) AS unit_sold
         FROM sales
         GROUP BY 
		 	sales.store_id,
			sales.product_id
        ), 
	inventory_cte 
	AS (
         SELECT 
		 	inventory.store_id,
            inventory.product_id,
            sum(inventory.stock_on_hand) AS total_inventory
          FROM inventory
          GROUP BY 
		  	inventory.store_id,
			 inventory.product_id
		)
		
SELECT 
 	st.store_id,
    st.store_name,
    p.product_id,
    p.product_name,
    sc.unit_sold,
    ic.total_inventory,
    round(sc.unit_sold::numeric / NULLIF(ic.total_inventory, 0)::numeric, 2) AS inventory_turnover
FROM sales_cte sc
	JOIN stores st ON sc.store_id = st.store_id
    JOIN products p ON sc.product_id = p.product_id
    JOIN inventory_cte ic ON sc.product_id = ic.product_id 
		AND sc.store_id = ic.store_id;

-- =================================================================================
-- Inventory Turnover by Product
-- =================================================================================

CREATE OR REPLACE VIEW vw_product_inventory_turnover 
AS
	SELECT product_id,
	    product_name,
	    sum(unit_sold) AS units_sold,
	    sum(total_inventory) AS total_inventory,
	    round(sum(unit_sold) / NULLIF(sum(total_inventory), 0::numeric), 2) AS inventory_turnover
	FROM vw_inventory_turnover
  	GROUP BY product_id, product_name;

-- =================================================================================
-- Revenue by Store
-- =================================================================================

CREATE OR REPLACE VIEW vw_store_revenue
AS
	SELECT 
	 	store_id,
	    store_name,
	    sum(revenue) AS revenue
   FROM vw_sales_performance
   GROUP BY store_id, store_name;


-- =================================================================================
-- Inventory Turnover by Store
-- =================================================================================

CREATE OR REPLACE VIEW vw_store_inventory_turnover
AS
	SELECT 
		store_id,
    	store_name,
    	sum(unit_sold) AS units_sold,
    	sum(total_inventory) AS total_inventory,
    	round(sum(unit_sold) / NULLIF(sum(total_inventory), 0::numeric), 2) 
			AS inventory_turnover
   	FROM vw_inventory_turnover vt
  	GROUP BY store_id, store_name;

-- =================================================================================
-- Inventory Reduction Analysis
-- =================================================================================

WITH product_metrics AS (
	SELECT
	    i.product_name,
	    i.units_sold,
	    i.total_inventory,
		p.product_cost,
		i.total_inventory * p.product_cost AS inventory_value,
	    i.inventory_turnover,
	    r.revenue
	FROM vw_product_inventory_turnover i
	JOIN products p
		ON i.product_id = p.product_id
	JOIN vw_product_revenue r
	    ON i.product_name = r.product_name
),
product_ranking AS (
	SELECT
		product_name,
		units_sold,
		total_inventory,
		product_cost,
		inventory_value,
		inventory_turnover,
		revenue,
		RANK () OVER (
			ORDER BY inventory_value ASC
		) AS inventory_value_rank,
		RANK () OVER (
			ORDER BY inventory_turnover DESC
		) AS turnover_rank,
		RANK ()	OVER (
			ORDER BY units_sold DESC
		) AS units_sold_rank,
		RANK () OVER (
			ORDER BY revenue DESC
		) AS revenue_rank
	FROM product_metrics
),
priority AS (
	SELECT
		*,
		inventory_value_rank 
		+ turnover_rank 
		+ units_sold_rank 
		+ revenue_rank 
			AS reduction_priority_score
	FROM product_ranking
),
target AS (
    SELECT
        *,
        SUM(inventory_value) OVER () AS total_inventory_value
    FROM priority
),
cumulative AS (
    SELECT
        *,
        SUM(inventory_value) OVER (
            ORDER BY 
				reduction_priority_score DESC,
				product_name			
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS cumulative_inventory_value
    FROM target
),
allocation AS (
    SELECT
        *,
        total_inventory_value * 0.20
            AS inventory_reduction_target,

        COALESCE(
            LAG(cumulative_inventory_value) OVER (
                ORDER BY 
					reduction_priority_score DESC,
					product_name
            ),
0
        ) AS previous_cumulative_inventory
    FROM cumulative
),

recommended AS (
    SELECT
        *,
        ROUND(
            CASE
                WHEN previous_cumulative_inventory
                     >= inventory_reduction_target
                THEN 0

                WHEN cumulative_inventory_value
                     <= inventory_reduction_target
                THEN inventory_value

                ELSE inventory_reduction_target
                     - previous_cumulative_inventory
            END,
            2
        ) AS recommended_reduction_value
    FROM allocation
)

SELECT
    product_name,
    inventory_value,
    inventory_turnover,
    units_sold,
    revenue,
    reduction_priority_score,

    ROUND(inventory_reduction_target,2)
		AS inventory_reduction_target,
	recommended_reduction_value,
  	ROUND(
	    recommended_reduction_value
	    / NULLIF(inventory_value, 0) * 100,
	    2
	) AS recommended_reduction_pct

FROM recommended
ORDER BY 
	reduction_priority_score DESC,
	product_name;

-- Insight :
-- A 20% reduction in inventory value represents approximately $59.99K. The reduction model prioritizes
-- products based on sales performance, inventory turnover, and inventory value, identifying which
-- products should contribute to the reduction first. The target is reached by fully reducing 12 high-priority
-- products and partially reducing Dinosaur Figures by 17.3%. Lower-priority products require no reduction under
-- the 20% target.

-- =================================================================================
-- Store Investment Analysis
-- =================================================================================
WITH store_metrics AS (
    SELECT
        i.store_id,
        i.store_name,
        i.units_sold,
        i.total_inventory,
        i.inventory_turnover,
        r.revenue
    FROM vw_store_inventory_turnover i
    JOIN vw_store_revenue r
        ON i.store_id = r.store_id
),

store_ranking AS (
    SELECT
        store_id,
        store_name,
        units_sold,
        total_inventory,
        inventory_turnover,
        revenue,

        RANK() OVER (
            ORDER BY revenue ASC
        ) AS revenue_rank,

        RANK() OVER (
            ORDER BY units_sold ASC
        ) AS units_sold_rank,

        RANK() OVER (
            ORDER BY inventory_turnover ASC
        ) AS turnover_rank,

        RANK() OVER (
            ORDER BY total_inventory DESC
        ) AS inventory_rank

    FROM store_metrics
),
-- Store investment priority:
-- Higher score indicates a stronger case for additional inventory.
-- The score combines equally weighted rankings for revenue, units sold,
-- inventory turnover, and inventory level.
-- Higher revenue and units sold, lower turnover, and lower inventory
-- receive higher priority in this scoring approach.
store_priority AS (
    SELECT
        *,
        revenue_rank
        + units_sold_rank
        + turnover_rank
        + inventory_rank
            AS investment_priority_score
    FROM store_ranking
),

final_ranking AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            ORDER BY investment_priority_score DESC
        ) AS investment_priority
    FROM store_priority
)

SELECT
    store_id,
    store_name,
    units_sold,
    total_inventory,
    inventory_turnover,
    revenue,
    investment_priority_score,
    investment_priority
FROM final_ranking
WHERE investment_priority <= 3
ORDER BY investment_priority;

-- Insight :
-- Guanajuato 1, Saltillo 1, and Ciudad de Mexico 1 rank highest on the equally weighted inventory
-- opportunity score, combining strong revenue and units sold with relatively lower inventory.
-- These stores should be considered for additional inventory based on their sales performance 
-- and current inventory position.


-- =================================================================================
-- Category Expansion Analysis
-- =================================================================================
WITH category_metrics AS (
    SELECT
        p.product_category,
        SUM(i.units_sold) AS units_sold,
        SUM(i.total_inventory) AS total_inventory,
        ROUND(
            SUM(i.units_sold)
            / NULLIF(SUM(i.total_inventory), 0),
            2
        ) AS inventory_turnover,
        SUM(r.revenue) AS revenue
    FROM vw_product_inventory_turnover i
    JOIN products p
        ON i.product_id = p.product_id
    JOIN vw_product_revenue r
        ON i.product_name = r.product_name
    GROUP BY
        p.product_category
),

normalized AS (
    SELECT
        *,
        
        (revenue - MIN(revenue) OVER ())
        / NULLIF(
            MAX(revenue) OVER () - MIN(revenue) OVER (),
            0
        ) AS revenue_score,

        (units_sold - MIN(units_sold) OVER ())
        / NULLIF(
            MAX(units_sold) OVER () - MIN(units_sold) OVER (),
            0
        ) AS units_sold_score,

        (inventory_turnover - MIN(inventory_turnover) OVER ())
        / NULLIF(
            MAX(inventory_turnover) OVER ()
            - MIN(inventory_turnover) OVER (),
            0
        ) AS turnover_score,

        (MAX(total_inventory) OVER () - total_inventory)
        / NULLIF(
            MAX(total_inventory) OVER ()
            - MIN(total_inventory) OVER (),
            0
        ) AS inventory_score

    FROM category_metrics
)
-- Inventory is scored inversely: lower inventory receives a higher score.
SELECT
    product_category,
    revenue,
    units_sold,
    total_inventory,
    inventory_turnover,

    ROUND(revenue_score, 3) AS revenue_score,
    ROUND(units_sold_score, 3) AS units_sold_score,
    ROUND(turnover_score, 3) AS turnover_score,
    ROUND(inventory_score, 3) AS inventory_score,

    ROUND(
        revenue_score * 0.30
        + units_sold_score * 0.30
        + turnover_score * 0.25
        + inventory_score * 0.15,
        3
    ) AS expansion_score

FROM normalized
ORDER BY expansion_score DESC;

-- Insight :
-- Expansion priority uses weighted scores:
-- Revenue 30%, Units Sold 30%, Inventory Turnover 25%, Inventory 15%.
-- Revenue and units sold receive the highest weights because they directly
-- reflect sales performance.

-- =================================================================================
-- Operational Improvement Analysis
-- =================================================================================

WITH store_metrics AS (
    SELECT
        i.store_id,
        i.store_name,
        i.units_sold,
        i.total_inventory,
        i.inventory_turnover,
        r.revenue
    FROM vw_store_inventory_turnover i
    JOIN vw_store_revenue r
        ON i.store_id = r.store_id
),

store_ranking AS (
    SELECT
        store_id,
        store_name,
        units_sold,
        total_inventory,
        inventory_turnover,
        revenue,

        RANK() OVER (
            ORDER BY revenue DESC
        ) AS revenue_rank,

        RANK() OVER (
            ORDER BY units_sold DESC
        ) AS units_sold_rank,

        RANK() OVER (
            ORDER BY inventory_turnover DESC
        ) AS turnover_rank,

        RANK() OVER (
            ORDER BY total_inventory ASC
        ) AS inventory_rank

    FROM store_metrics
),
-- Operational improvement priority:
-- Higher score indicates a greater need for operational review.
-- The score reflects relatively weak revenue, units sold, and inventory turnover,
-- together with relatively high inventory.
store_priority AS (
    SELECT
        *,
        revenue_rank
        + units_sold_rank
        + turnover_rank
        + inventory_rank
            AS operational_priority_score
    FROM store_ranking
)

SELECT
    store_id,
    store_name,
    units_sold,
    total_inventory,
    inventory_turnover,
    revenue,
    revenue_rank,
    units_sold_rank,
    turnover_rank,
    inventory_rank,
    operational_priority_score

FROM store_priority
ORDER BY operational_priority_score DESC;

-- Insight :
-- Stores were ranked based on revenue, units sold, inventory turnover, and current inventory to identify
-- locations with weak sales performance and inefficient inventory utilization. Stores with weak revenue
-- and units sold, low inventory turnover, and relatively high inventory should be prioritized for
-- operational improvement before additional inventory investment.
