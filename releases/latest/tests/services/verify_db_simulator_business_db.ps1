param(
    [string]$EnvFile = "deployment/env/local.env",
    [string]$ComposeFile = "deployment/docker-compose.yml"
)

$ErrorActionPreference = "Stop"

docker compose --env-file $EnvFile -f $ComposeFile up -d business-db db-simulator | Out-Null

$deadline = (Get-Date).AddSeconds(60)
do {
    $status = docker inspect -f "{{.State.Health.Status}}" ai20-business-db-1 2>$null
    if ($status -eq "healthy") {
        break
    }
    Start-Sleep -Seconds 2
} while ((Get-Date) -lt $deadline)

if ($status -ne "healthy") {
    throw "business-db did not become healthy; status=$status"
}

$sql = @"
insert into core.customers (platform, platform_customer_id, nickname)
values ('test', 'customer-dbtest', 'DB Test Customer')
on conflict (platform, platform_customer_id) do update set nickname = excluded.nickname;

insert into commerce.products (sku_id, name, category, price, stock, status, description)
values ('SKU-DBTEST', 'DB Test Product', 'test-category', 12.34, 56, 'active', 'Product from business database')
on conflict (sku_id) do update set
  name = excluded.name,
  category = excluded.category,
  price = excluded.price,
  stock = excluded.stock,
  status = excluded.status,
  description = excluded.description;

with customer_row as (
  select id from core.customers where platform = 'test' and platform_customer_id = 'customer-dbtest'
)
insert into commerce.orders (order_id, customer_id, platform, status, total_amount, recipient_name, phone_masked, shipping_address_masked, logistics_company, logistics_no, ordered_at)
select 'ORD-DBTEST', id, 'test', 'shipped', 12.34, 'Test User', '188****0000', 'Test Address', 'Test Express', 'TRACK-DBTEST', now()
from customer_row
on conflict (order_id) do update set
  status = excluded.status,
  total_amount = excluded.total_amount,
  recipient_name = excluded.recipient_name,
  phone_masked = excluded.phone_masked,
  shipping_address_masked = excluded.shipping_address_masked,
  logistics_company = excluded.logistics_company,
  logistics_no = excluded.logistics_no;

with order_row as (
  select id from commerce.orders where order_id = 'ORD-DBTEST'
),
product_row as (
  select id from commerce.products where sku_id = 'SKU-DBTEST'
)
insert into commerce.order_items (order_id, product_id, sku_id, product_name, quantity, unit_price, total_price)
select order_row.id, product_row.id, 'SKU-DBTEST', 'DB Test Product', 1, 12.34, 12.34
from order_row, product_row
where not exists (
  select 1 from commerce.order_items oi where oi.order_id = order_row.id and oi.sku_id = 'SKU-DBTEST'
);

with order_row as (
  select id from commerce.orders where order_id = 'ORD-DBTEST'
)
insert into commerce.logistics (tracking_no, order_id, company, status, estimated_delivery)
select 'TRACK-DBTEST', id, 'Test Express', 'in_transit', current_date + 1
from order_row
on conflict (tracking_no) do update set
  status = excluded.status,
  estimated_delivery = excluded.estimated_delivery;
"@

$tmpSql = "/tmp/db-simulator-business-db-test.sql"
$sql | docker exec -i ai20-business-db-1 sh -c "cat > $tmpSql"
docker exec ai20-business-db-1 psql -U app_user -d app_business -f $tmpSql | Out-Null

$product = Invoke-RestMethod -Uri "http://localhost:8001/api/product/SKU-DBTEST" -TimeoutSec 20
if ($product.data.sku_id -ne "SKU-DBTEST") {
    throw "db-simulator did not return product from business-db"
}

$order = Invoke-RestMethod -Uri "http://localhost:8001/api/order/ORD-DBTEST" -TimeoutSec 20
if ($order.data.order_id -ne "ORD-DBTEST") {
    throw "db-simulator did not return order from business-db"
}

$logistics = Invoke-RestMethod -Uri "http://localhost:8001/api/logistics/TRACK-DBTEST" -TimeoutSec 20
if ($logistics.data.tracking_no -ne "TRACK-DBTEST") {
    throw "db-simulator did not return logistics from business-db"
}

"OK db-simulator business-db integration verified"
