with params as (
  select
    240 as collecting_months,
    100 as monthly_saving,
    1300 as latest_start_month
),
starting_months as (
  select 
    month
  from params
    join unnest(generate_array(1, params.latest_start_month)) month
),
/*
monthly_rates as (
  select 
    month,
    pow(pow(1.00, 1/12), month) as price
  from unnest(generate_array(1, 1000)) month
),
*/
monthly_rates as (
  select 
    row_number() over () as month,
    `Real price` as price
  from random.sp500
  order by Date asc
),
running_savings as (
  select
    monthly_rates.month as month,
    starting_months.month as starting_month,
    price,
    case when monthly_rates.month >= starting_months.month
      then params.monthly_saving / price
      else 0 end as share_bought
  from monthly_rates
    join params on 1=1
    join starting_months on 1=1
),
all_shares_bought as (
  select
    starting_month,
    sum(case when share_bought > 0 then 1 else 0 end) as cnt_check,
    sum(share_bought) as value,
    avg(monthly_rates.price) as final_price,
    sum(share_bought) * avg(monthly_rates.price) as final_value
  from running_savings
    join params on 1=1
    join monthly_rates on monthly_rates.month = collecting_months + starting_month - 1
  where running_savings.month < collecting_months + starting_month
  group by starting_month
),
retirement_months as (
  select 
    monthly_rates.month,
    starting_months.month as starting_month,
    price,
    params.monthly_saving / price as share_sold
  from monthly_rates
  join params on 1=1
  join starting_months on 1=1
    where monthly_rates.month >= params.collecting_months + starting_months.month
),
retirement_months_cum as (
  select 
    month,
    starting_month,
    sum(share_sold) over (partition by starting_month order by month) as share_sold_cum,
    price
  from retirement_months
),
retirement_months_count as (
  select
    count(*) as retirement_months,
    all_shares_bought.starting_month,
    max(share_sold_cum) as all_sold,
    max(all_shares_bought.value) as all_bought,
    avg(price) as avg_price
  from retirement_months_cum
  join all_shares_bought on all_shares_bought.starting_month = retirement_months_cum.starting_month
    where share_sold_cum <= all_shares_bought.value
  group by starting_month
),
retirement_months_count_adjusted as (
  select
    retirement_months
      + cast(round(greatest(all_bought - all_sold, 0) * avg_price / params.monthly_saving) as int64)
     as retirement_months,
  starting_month
  from retirement_months_count
    join params on 1=1
),
retirement_months_count_capped as (
  select
    starting_month,
    least(480, retirement_months) as retirement_months
  from retirement_months_count_adjusted
),
with_dates as (
select
  starting_month,
  date_add(date('1871-01-01'), interval starting_month month) as starting_date,
  date_add(date('1871-01-01'), interval starting_month + params.collecting_months month) as retirement_date,
  date_add(date('1871-01-01'), interval starting_month + params.collecting_months + retirement_months month) as savings_run_out_at,
  params.collecting_months,
  retirement_months_count_capped.retirement_months
  from retirement_months_count_capped
  join params on 1=1
order by retirement_months desc
)

select * from with_dates