-- Users Table
CREATE TABLE users (
    user_id TEXT PRIMARY KEY,
    name TEXT,
    email TEXT UNIQUE,
    state TEXT,
    product_id TEXT,
    vendor_id TEXT,
    product_fssai_code BIGINT,
    complaint_text TEXT,
    complaint_status TEXT,
    complaint_priority TEXT,
    complaint_date DATE,
    complaint_image_url TEXT,
    rating INT,
    review TEXT,
    review_date DATE,
    review_sentiment TEXT
);

-- Products Table
CREATE TABLE products (
    product_id TEXT PRIMARY KEY,
    product_name TEXT,
    category TEXT,
    vendor_id TEXT,
    fssai_code BIGINT,
    is_verified BOOLEAN
);

-- Vendors Table
CREATE TABLE vendors (
    vendor_id TEXT PRIMARY KEY,
    vendor_name TEXT,
    state TEXT,
    fssai_code BIGINT,
    total_complaints INT,
    unresolved_complaints INT,
    trust_score NUMERIC(5,2)
);

select * from users
limit 5
select count(*) from users

select * from products
limit 5
select count(*) from products

select * from vendors
limit 5
select count(*) from vendors


UPDATE users
SET complaint_status = 'Not Complained'
WHERE complaint_status IS NULL;

UPDATE users
SET complaint_priority = 'Not Complained'
WHERE complaint_priority IS NULL;

UPDATE users
SET complaint_image_url = 'Not Complained'
WHERE complaint_image_url IS NULL;

UPDATE users
SET review = 'Not Provided'
WHERE review IS NULL;

select * from users

