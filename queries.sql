-- Q1: Monthly Revenue
SELECT DATE_TRUNC('month', o.order_purchase_timestamp) AS month,
       COUNT(DISTINCT o.order_id) AS orders,
       ROUND(SUM(oi.price)::numeric, 2) AS revenue
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY 1
ORDER BY 1;

-- Q2: Month-over-Month Growth
WITH monthly AS (
  SELECT DATE_TRUNC('month', o.order_purchase_timestamp) AS month,
         ROUND(SUM(oi.price)::numeric, 2) AS revenue
  FROM orders o
  JOIN order_items oi ON o.order_id = oi.order_id
  WHERE o.order_status = 'delivered'
    AND o.order_delivered_customer_date IS NOT NULL
  GROUP BY 1
)
SELECT month,
       revenue,
       ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month))
             / LAG(revenue) OVER (ORDER BY month), 1) AS mom_growth_pct
FROM monthly
WHERE month >= '2017-01-01' AND month <= '2018-08-01'
ORDER BY month;

-- Q3: Late Delivery Rate
SELECT ROUND(100.0 * COUNT(*) FILTER (
         WHERE order_delivered_customer_date > order_estimated_delivery_date) / COUNT(*), 2) AS late_pct
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL;

-- Q4: Review Score by Delivery Status
SELECT CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
            THEN 'Late' ELSE 'On time' END AS delivery,
       ROUND(AVG(r.review_score), 2) AS avg_review,
       COUNT(*) AS orders
FROM orders o
JOIN order_reviews r ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY 1;

-- Q5: Repeat Customer Rate
SELECT COUNT(*) FILTER (WHERE order_count > 1) AS repeat_customers,
       COUNT(*) AS total_customers,
       ROUND(100.0 * COUNT(*) FILTER (WHERE order_count > 1) / COUNT(*), 2) AS repeat_pct
FROM (
  SELECT c.customer_unique_id, COUNT(DISTINCT o.order_id) AS order_count
  FROM customers c
  JOIN orders o ON c.customer_id = o.customer_id
  GROUP BY 1
) t;

-- Q6: Top 10 Categories by Revenue
SELECT t.product_category_name_english AS category,
       ROUND(SUM(oi.price)::numeric, 2) AS revenue,
       COUNT(DISTINCT oi.order_id) AS orders
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
JOIN product_category_name_translation t ON p.product_category_name = t.product_category_name
GROUP BY 1
ORDER BY revenue DESC
LIMIT 10;

-- Q7: Top 3 Sellers by State
SELECT * FROM (
  SELECT s.seller_state, s.seller_id,
         ROUND(SUM(oi.price)::numeric, 2) AS revenue,
         RANK() OVER (PARTITION BY s.seller_state ORDER BY SUM(oi.price) DESC) AS rnk
  FROM order_items oi
  JOIN sellers s ON oi.seller_id = s.seller_id
  GROUP BY 1, 2
) t
WHERE rnk <= 3
ORDER BY seller_state, rnk;

-- Q8: Payment Type Share
SELECT payment_type,
       COUNT(*) AS payments,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_share
FROM order_payments
GROUP BY 1
ORDER BY payments DESC;

-- Query A: Late Delivery Rate by State
SELECT c.customer_state,
       COUNT(*) AS total_orders,
       COUNT(*) FILTER (WHERE o.order_delivered_customer_date > o.order_estimated_delivery_date) AS late_orders,
       ROUND(100.0 * COUNT(*) FILTER (WHERE o.order_delivered_customer_date > o.order_estimated_delivery_date) / COUNT(*), 2) AS late_pct
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL
GROUP BY 1
HAVING COUNT(*) > 100
ORDER BY late_pct DESC;

-- Query B: Same-State vs Different-State Delivery
SELECT CASE WHEN s.seller_state = c.customer_state THEN 'Same state' ELSE 'Different state' END AS route,
       COUNT(*) AS orders,
       ROUND(100.0 * COUNT(*) FILTER (WHERE o.order_delivered_customer_date > o.order_estimated_delivery_date) / COUNT(*), 2) AS late_pct,
       ROUND(AVG(EXTRACT(DAY FROM o.order_delivered_customer_date - o.order_purchase_timestamp)), 1) AS avg_delivery_days
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
JOIN order_items oi ON o.order_id = oi.order_id
JOIN sellers s ON oi.seller_id = s.seller_id
WHERE o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL
GROUP BY 1;
-- Query C: Master view for Tableau (one row per order item, delivered orders only)
-- Exported as dashboard-data/orders_master.csv and used by every chart and KPI card.
CREATE OR REPLACE VIEW orders_master_v AS
SELECT o.order_id,
       o.order_purchase_timestamp::date AS order_date,
       EXTRACT(YEAR FROM o.order_purchase_timestamp)::int AS order_year,
       DATE_TRUNC('month', o.order_purchase_timestamp)::date AS order_month,
       c.customer_state,
       c.customer_unique_id,
       COALESCE(t.product_category_name_english, 'unknown') AS category,
       oi.price,
       oi.freight_value,
       (o.order_delivered_customer_date::date - o.order_purchase_timestamp::date) AS delivery_days,
       CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
            THEN 1 ELSE 0 END AS is_late,
       r.review_score
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
JOIN customers c ON o.customer_id = c.customer_id
LEFT JOIN products p ON oi.product_id = p.product_id
LEFT JOIN product_category_name_translation t ON p.product_category_name = t.product_category_name
LEFT JOIN (SELECT order_id, AVG(review_score) AS review_score
           FROM order_reviews GROUP BY order_id) r ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL;

SELECT * FROM orders_master_v;
