-- Create the new database if it does not already exist
CREATE DATABASE IF NOT EXISTS `ReturnProcessingAgent`;
USE `ReturnProcessingAgent`;

-- Creating the Damage Policy table
CREATE TABLE DamagePolicy (
    DamagePolicyID VARCHAR(10) PRIMARY KEY,
    ProductCategory VARCHAR(100) UNIQUE,
    DamagePolicyCondition TEXT  -- Multiline text describing acceptable damage conditions
);

-- Creating the Product table with a reference to DamagePolicyID
CREATE TABLE Product (
    ProductID VARCHAR(10) PRIMARY KEY,
    ProductName VARCHAR(255) NOT NULL,
    ProductDescription TEXT,
    ProductCategory VARCHAR(100),
    ProductPrice DECIMAL(10, 2),
    ReturnEligible ENUM('Yes', 'No') DEFAULT 'Yes',
    RefundEligibility VARCHAR(10) DEFAULT '30',
    ProductImages JSON,  -- Storing image URLs as a JSON array for AI recognition
    DamagePolicyID VARCHAR(10),  -- Reference to DamagePolicy
    FOREIGN KEY (DamagePolicyID) REFERENCES DamagePolicy(DamagePolicyID),
    CHECK (ReturnEligible = 'No' AND RefundEligibility = 'N/A' OR ReturnEligible = 'Yes')
);

-- Creating the Customer table
CREATE TABLE Customer (
    CustomerID INT AUTO_INCREMENT PRIMARY KEY,
    FullName VARCHAR(255) NOT NULL,
    Address TEXT,
    PhoneNumber CHAR(10),
    CHECK (CHAR_LENGTH(PhoneNumber) = 10)
);

-- Creating the Order table with additional fields for return processing
CREATE TABLE `Order` (
    OrderID VARCHAR(10) PRIMARY KEY,
    CustomerID INT,
    ProductID VARCHAR(10),
    ProductCategory VARCHAR(100),  -- To be auto-populated based on ProductID
    OrderQty INT,
    OrderAmount DECIMAL(10, 2),
    OrderDate DATE,
    DeliveryDate DATE,
    ReturnEligibleDate DATE,  -- To be auto-populated based on delivery and refund eligibility
    OrderReturned ENUM('Yes', 'No') DEFAULT 'No',
    ReturnDate DATE DEFAULT NULL,  -- To be populated based on QR code scanned date
    DamagePolicyID VARCHAR(10),
    FOREIGN KEY (CustomerID) REFERENCES Customer(CustomerID),
    FOREIGN KEY (ProductID) REFERENCES Product(ProductID),
    FOREIGN KEY (DamagePolicyID) REFERENCES DamagePolicy(DamagePolicyID)
);
CREATE TABLE `Order` (
    OrderID VARCHAR(10) PRIMARY KEY,
    CustomerID INT,
    ProductID VARCHAR(10),
    ProductCategory VARCHAR(100),  -- To be auto-populated based on ProductID
    OrderQty INT,
    OrderAmount DECIMAL(10, 2),  -- Calculated field
    OrderDate DATE,
    DeliveryDate DATE,
    ReturnEligibleDate DATE,  -- To be auto-populated based on delivery and refund eligibility
    DamagePolicyID VARCHAR(10),
    FOREIGN KEY (CustomerID) REFERENCES Customer(CustomerID),
    FOREIGN KEY (ProductID) REFERENCES Product(ProductID),
    FOREIGN KEY (DamagePolicyID) REFERENCES DamagePolicy(DamagePolicyID)
);

CREATE TABLE ReturnedOrders (
    OrderID VARCHAR(10),
    CustomerID INT,
    ProductID VARCHAR(10),
    OrderQtyReturned INT,
    RefundAmount DECIMAL(10, 2),
    ReturnedDate DATE,
    FOREIGN KEY (OrderID) REFERENCES `Order`(OrderID),
    FOREIGN KEY (CustomerID) REFERENCES Customer(CustomerID),
    FOREIGN KEY (ProductID) REFERENCES Product(ProductID)
);

DELIMITER $$

CREATE TRIGGER SetReturnedDate BEFORE INSERT ON ReturnedOrders
FOR EACH ROW
BEGIN
    SET NEW.ReturnedDate = CURRENT_DATE();
END$$

DELIMITER ;

DELIMITER $$

CREATE TRIGGER SetDamagePolicyID BEFORE INSERT ON `Order`
FOR EACH ROW
BEGIN
    DECLARE damage_policy_id VARCHAR(10);
    
    -- Fetch the DamagePolicyID from the Product table based on the ProductID of the new order
    SELECT DamagePolicyID INTO damage_policy_id FROM Product WHERE ProductID = NEW.ProductID;

    -- Set the DamagePolicyID in the new order
    SET NEW.DamagePolicyID = damage_policy_id;
END$$

DELIMITER ;


-- Trigger to calculate OrderAmount before an order is inserted
DELIMITER $$
CREATE TRIGGER CalculateOrderAmount BEFORE INSERT ON `Order`
FOR EACH ROW
BEGIN
    SELECT ProductPrice INTO @price FROM Product WHERE ProductID = NEW.ProductID;
    SET NEW.OrderAmount = NEW.OrderQty * @price;
END$$
DELIMITER ;

-- Set delimiters for defining triggers and procedures
DELIMITER $$

-- Trigger to automatically populate ReturnEligibleDate and ProductCategory before inserting a new order
CREATE TRIGGER AutoSetOrderDetails BEFORE INSERT ON `Order`
FOR EACH ROW
BEGIN
    DECLARE refundDays INT;
    DECLARE category VARCHAR(100);
    
    -- Fetch refund eligibility and category from Product
    SELECT RefundEligibility, ProductCategory INTO refundDays, category
    FROM Product 
    WHERE ProductID = NEW.ProductID;
    
    -- Set ReturnEligibleDate and ProductCategory
    SET NEW.ReturnEligibleDate = DATE_ADD(NEW.DeliveryDate, INTERVAL refundDays DAY),
        NEW.ProductCategory = category;
END$$

-- Triggers for automatic DamagePolicyID assignment
CREATE TRIGGER AutoSetDamagePolicyIDBeforeInsert BEFORE INSERT ON Product
FOR EACH ROW
BEGIN
    SET NEW.DamagePolicyID = (
        SELECT DamagePolicyID 
        FROM DamagePolicy 
        WHERE ProductCategory = NEW.ProductCategory
        LIMIT 1
    );
END$$

CREATE TRIGGER AutoSetDamagePolicyIDBeforeUpdate BEFORE UPDATE ON Product
FOR EACH ROW
BEGIN
    SET NEW.DamagePolicyID = (
        SELECT DamagePolicyID 
        FROM DamagePolicy 
        WHERE ProductCategory = NEW.ProductCategory
        LIMIT 1
    );
END$$

DELIMITER ;

-- Insert statements for the Customer table
-- Start a transaction to ensure all or nothing execution
START TRANSACTION;
-- Delete all records from the Customer table
DELETE FROM Customer;
-- Reset the auto-increment value of CustomerID to start from 1
ALTER TABLE Customer AUTO_INCREMENT = 1;
-- Insert new customer data with email addresses
INSERT INTO Customer (FullName, Address, PhoneNumber, Email) VALUES
('John Doe', '123 Elm St, Springfield, IL', '3125550198', 'john.doe@example.com'),
('Jane Smith', '456 Maple Ave, Dayton, OH', '9375550123', 'jane.smith@example.com'),
('Alice Johnson', '789 Oak Blvd, Tampa, FL', '8135550271', 'alice.johnson@example.com'),
('Chris Lee', '321 Pine Street, Dallas, TX', '2145550392', 'chris.lee@example.com'),
('Patricia Brown', '654 Cedar Ct, Phoenix, AZ', '6025550463', 'patricia.brown@example.com'),
('Ella Davis', '987 Spruce Rd, Sacramento, CA', '9165550534', 'ella.davis@example.com'),
('Marco Garcia', '234 Fir Lane, Orlando, FL', '4075550675', 'marco.garcia@example.com'),
('Lily White', '567 Birch Parkway, Denver, CO', '3035550746', 'lily.white@example.com'),
('Samuel Black', '890 Palm Drive, Miami, FL', '3055550817', 'samuel.black@example.com'),
('Nora Gray', '123 Magnolia Ave, Seattle, WA', '2065550988', 'nora.gray@example.com');
ALTER TABLE Customer
ADD passwords VARCHAR(255);
UPDATE Customer SET passwords = CONCAT(LEFT(FullName, INSTR(FullName, ' ') - 1), '1234') WHERE CustomerID = 1;
UPDATE Customer SET passwords = CONCAT(LEFT(FullName, INSTR(FullName, ' ') - 1), '1234') WHERE CustomerID = 2;
UPDATE Customer SET passwords = CONCAT(LEFT(FullName, INSTR(FullName, ' ') - 1), '1234') WHERE CustomerID = 3;
UPDATE Customer SET passwords = CONCAT(LEFT(FullName, INSTR(FullName, ' ') - 1), '1234') WHERE CustomerID = 4;
UPDATE Customer SET passwords = CONCAT(LEFT(FullName, INSTR(FullName, ' ') - 1), '1234') WHERE CustomerID = 5;
UPDATE Customer SET passwords = CONCAT(LEFT(FullName, INSTR(FullName, ' ') - 1), '1234') WHERE CustomerID = 6;
UPDATE Customer SET passwords = CONCAT(LEFT(FullName, INSTR(FullName, ' ') - 1), '1234') WHERE CustomerID = 7;
UPDATE Customer SET passwords = CONCAT(LEFT(FullName, INSTR(FullName, ' ') - 1), '1234') WHERE CustomerID = 8;
UPDATE Customer SET passwords = CONCAT(LEFT(FullName, INSTR(FullName, ' ') - 1), '1234') WHERE CustomerID = 9;
UPDATE Customer SET passwords = CONCAT(LEFT(FullName, INSTR(FullName, ' ') - 1), '1234') WHERE CustomerID = 10;

-- Commit the transaction to make sure all operations are saved
COMMIT;
############

######### Inserting into damage policy tables
-- Insert statements for the DamagePolicy table
-- Insert initial damage policies for various product categories
INSERT INTO DamagePolicy (DamagePolicyID, ProductCategory, DamagePolicyCondition) VALUES
('DP01', 'Electronics', 'No physical destruction; the product must be free of damage, scratches, or dents. It should be returned with original packaging, including all labels, tags, and any accompanying paperwork.'),
('DP02', 'Clothing', 'No tears, scratches, color variations, or size discrepancies from the shipped product. All original tags, labels, and packaging materials must be included upon return.'),
('DP03', 'Home Equipment', 'Product must be returned in original working condition without any damage or signs of use. All components, accessories, and manuals must be included.'),
('DP04', 'Furniture', 'Must be free from wear, tear, stains, and structural damage. All hardware components should be included, and the item must be disassembled in the original packaging method if applicable.'),
('DP05', 'Books', 'No torn or missing pages, no water damage, and no markings or annotations. Must include any original dust jackets or coverings.'),
('DP06', 'Food', 'Returns not accepted unless the product is received damaged. Must provide photographic evidence of damage upon receipt for return eligibility.');
INSERT INTO DamagePolicy (DamagePolicyID, ProductCategory, DamagePolicyCondition) VALUES
('DP07', 'Personal Care', 'Products must be unopened and in original sealed packaging. No signs of use or tampering should be evident. Items must include all original components, accessories, and instructions.');
INSERT INTO DamagePolicy (DamagePolicyID, ProductCategory, DamagePolicyCondition) VALUES
('DP08', 'Kitchen Utensils', 'Items must be returned with no signs of wear and tear, fully functional, and include all original packaging and accessories. Any scratches, dents, or functional impairments will disqualify the product from return.'),
('DP09', 'Glassware Items', 'All glassware must be returned without any cracks, chips, or breaks. Products must be returned in their original packaging with sufficient protective material to prevent damage during transit.');
INSERT INTO DamagePolicy (DamagePolicyID, ProductCategory, DamagePolicyCondition) VALUES
('DP10', 'Appliances', 'Appliances must be returned in their original functional condition without any physical damage. They must include all original accessories, manuals, and warranty information. Any signs of misuse, unauthorized repairs, or modifications will render the return invalid.');

UPDATE DamagePolicy 
SET DamagePolicyCondition = 'Appliances must be returned in their original functional condition without any physical damage. They must include all original accessories, manuals, and warranty information. Any signs of misuse, unauthorized repairs, or modifications will render the return invalid.'
WHERE DamagePolicyID = 'DP10';

-- Enhancements for Electronics and Clothing with additional conditions
UPDATE DamagePolicy
SET DamagePolicyCondition = CONCAT(DamagePolicyCondition, ' Additionally, electronic items must include all warranty cards and unexpired warranties.')
WHERE ProductCategory = 'Electronics';

UPDATE DamagePolicy
SET DamagePolicyCondition = CONCAT(DamagePolicyCondition, ' Fabric condition must be verified as unworn and unwashed.')
WHERE ProductCategory = 'Clothing';

-- General clause for all products regarding return if received damaged
UPDATE DamagePolicy
SET DamagePolicyCondition = CONCAT(DamagePolicyCondition, ' If the product is received damaged, it may be returned within the return window, subject to verification.')
WHERE ProductCategory <> 'Food';  -- Exclude Food because it has a specific non-returnable policy unless damaged

#########################
## Inserting records into products table
INSERT INTO Product (ProductID, ProductName, ProductDescription, ProductCategory, ProductPrice, ReturnEligible, RefundEligibility, ProductImages) VALUES
('P001', 'Amazon Fire TV Stick HD (newest model), free and live TV, Alexa Voice Remote, smart home controls, HD streaming', 
'Amazon''s Fire TV devices are a cheap and easy way to connect Smart and not-so-Smart TVs to WiFi and download, install, and run third-party apps on your TV', 
'Electronics', 23.99, 'Yes', '30', 
'["https://m.media-amazon.com/images/I/61weCavnG7L._AC_SY450_.jpg", "https://m.media-amazon.com/images/I/51GHEdUznQL._AC_SY450_.jpg", "https://m.media-amazon.com/images/I/81Kf-msToOL._AC_SY450_.jpg", "https://m.media-amazon.com/images/I/81FGhg8D0yL._AC_SY450_.jpg", "https://m.media-amazon.com/images/I/81CSSbdjsrL._AC_SY450_.jpg", "https://m.media-amazon.com/images/I/81+pJqQvatL._AC_SY450_.jpg", "https://m.media-amazon.com/images/I/81QsyQB6XjL._AC_SY450_.jpg"]');
INSERT INTO Product (ProductID, ProductName, ProductDescription, ProductCategory, ProductPrice, ReturnEligible, RefundEligibility, ProductImages) VALUES
('P002', 'Cetaphil Ultra Gentle Refreshing Body Wash, For Dry to Normal, Sensitive Skin, 16.9oz, with Aloe Vera, Calendula, Vitamin B5, Hypoallergenic, Fragrance Free, Dermatologist Tested', 'Body talcum powder', 'Personal Care', 7.28, 'Yes', '30', '["https://m.media-amazon.com/images/I/61A4ofkfKAL._SX679_.jpg", "https://m.media-amazon.com/images/I/71Uenp9yN9L._SX679_.jpg", "https://m.media-amazon.com/images/I/910Z4MY08gL._SX679_.jpg"]'),
('P003', 'COSRX Snail Mucin 96% Power Repairing Essence 3.38 fl.oz 100ml', 'Hydrating Serum for Face with Snail Secretion Filtrate for Dull Skin & Fine Lines, Korean Skin Care', 'Personal care', 18.99, 'Yes', '30', '["https://m.media-amazon.com/images/I/61p-wtpDraL._SX679_.jpg", "https://m.media-amazon.com/images/I/71VWH32nDWL._SX679_.jpg"]'),
('P004', 'Razer Basilisk V3 X HyperSpeed Wireless Gaming Mouse: Up to 285 Hr Battery - 18K Optical Sensor - Mechanical Switches - Chroma RGB - 9 Programmable Controls - Black', 'Gaming mouse', 'Electronics', 59.99, 'Yes', '60', '["https://m.media-amazon.com/images/I/61okFRY8uPL._AC_SX425_.jpg", "https://m.media-amazon.com/images/I/71-Wn8LEQvL._AC_SL1500_.jpg", "https://m.media-amazon.com/images/I/71MYbZEyejL._AC_SL1500_.jpg", "https://m.media-amazon.com/images/I/719q8upc7hL._AC_SL1500_.jpg"]'),
('P005', 'SAMSUNG 65-Inch Class OLED 4K S90D Series HDR+', 'Smart TV w/Dolby Atmos, Object Tracking Sound Lite, Motion Xcelerator, Real Depth Enhancer, 4K AI Upscaling, Alexa Built-in (QN65S90D, 2024 Model)', 'Electronics', 1497, 'Yes', '60', '["https://m.media-amazon.com/images/I/71kI34+jBAL._AC_SX425_.jpg", "https://m.media-amazon.com/images/I/61pEA-rTNtL._AC_SX425_.jpg", "https://m.media-amazon.com/images/I/41Nd42V89XL._AC_SL1500_.jpg", "https://m.media-amazon.com/images/I/815Yyw6WAHL._AC_SL1500_.jpg"]'),
('P006', 'Beats Solo 4 - Wireless Bluetooth On-Ear Headphones, Apple & Android Compatible, Up to 50 Hours of Battery Life - Matte Black', 'Wireless Bluetooth On-Ear Headphones', 'Electronics', 129.95, 'Yes', '60', '["https://m.media-amazon.com/images/I/515FE+S4yLL._AC_SX425_.jpg", "https://m.media-amazon.com/images/I/51IO9hIYPrL._AC_SL1500_.jpg"]'),
('P007', 'Beats Studio Buds - True Wireless Noise Cancelling Earbuds - Compatible with Apple & Android, Built-in Microphone, IPX4 Rating, Sweat Resistant Earphones, Class 1 Bluetooth Headphones - Black', 'Noise Cancelling Earbuds', 'Electronics', 99.95, 'Yes', '30', '["https://m.media-amazon.com/images/I/51bRSWrEc7S._AC_SX425_.jpg", "https://m.media-amazon.com/images/I/41OvvMbyc2S._AC_SL1500_.jpg"]'),
('P008', 'Apple Watch Ultra 2 [GPS + Cellular 49mm] Smartwatch, Sport Watch with Black Titanium Case with Dark Green Alpine Loop - S. Fitness Tracker, Precision GPS, Action Button, Carbon Neutral', 'Digital Watch', 'Electronics', 769, 'Yes', '30', '["https://m.media-amazon.com/images/I/81vLYHVwqjL._AC_SX425_.jpg", "https://m.media-amazon.com/images/I/71zAWc5+VYL._AC_SX425_.jpg", "https://m.media-amazon.com/images/I/71l4XRVDGZL._AC_SX425_.jpg"]'),
('P009', 'Apple iPad Pro 13-Inch (M4): Built for Apple Intelligence, Ultra Retina XDR Display, 256GB, 12MP Front/Back Camera, LiDAR Scanner, Wi-Fi 6E, Face ID, All-Day Battery Life — Space Black', 'Digital Ipad', 'Electronics', 1099, 'Yes', '60', '["https://m.media-amazon.com/images/I/7147JzEtrqL._AC_SX679_.jpg", "https://m.media-amazon.com/images/I/714-7INRdwL._AC_SX679_.jpg"]'),
('P010', 'Butternut Mountain Farm Pure Vermont Maple Syrup, Grade A, Dark Color, Robust Taste, All Natural, Easy Pour, 32 Fl Oz, 1 Qt (Prev Grade B)', 'Maple syrup', 'Food', 17.26, 'Yes', '30', '["https://m.media-amazon.com/images/I/71hsOdgfKrL._SY741_.jpg", "https://m.media-amazon.com/images/I/61nX2OstZ9L._SX679_.jpg"]');
INSERT INTO Product (ProductID, ProductName, ProductDescription, ProductCategory, ProductPrice, ReturnEligible, RefundEligibility, ProductImages) VALUES
('P011', 'HIWARE 1000ml Glass Teapot with Removable Infuser, Stovetop Safe Tea Kettle, Blooming and Loose Leaf Tea Maker Set', 'Tea Kettle', 'Glassware items', 19.8, 'Yes', '30', '["https://m.media-amazon.com/images/I/71TkR7JSRnL._AC_SX569_.jpg", "https://m.media-amazon.com/images/I/71-GT92SIeL._AC_SX569_.jpg"]'),
('P012', '6 PACK Premium Glass Coffee Mugs with Handle, 12 OZ Classic Vertical Stripes Glass Coffee Cups, Transparent Tea Cup for Hot/Cold Beverages, Glassware Set for Americano, Latte, Cappuccino', 'Glass coffee mugs', 'Glassware items', 21.99, 'Yes', '60', '["https://m.media-amazon.com/images/I/61BQPehZNuL._AC_SX569_.jpg", "https://m.media-amazon.com/images/I/71CWghjtvQL._AC_SX569_.jpg"]'),
('P013', 'FEZIBO Electric Standing Desk Adjustable Height, 55 x 24 Inch Sit and Stand Desk, Home Office Desk, Ergonomic Workstation Computer Desk, Maple', 'Electric Standing Desk', 'Furniture', 109, 'Yes', '30', '["https://m.media-amazon.com/images/I/61iwd3ITxCL._AC_SX569_.jpg", "https://m.media-amazon.com/images/I/81RLGj2BDGL._AC_SX569_.jpg", "https://m.media-amazon.com/images/I/71AHUn0Gc2L._AC_SX569_.jpg"]'),
('P014', 'Recliner Chair with Massage and Lumbar Support, Small Fabric Home Theater Seating, Adjustable Modern Reclining Chair for Adults in Living Room', 'Reclining Chair', 'Furniture', 139.99, 'Yes', '30', '["https://m.media-amazon.com/images/I/71FOR3dqLmL._AC_SX522_.jpg", "https://m.media-amazon.com/images/I/71OHg4k3G0L._AC_SX522_.jpg", "https://m.media-amazon.com/images/I/71X39iA0h1L._AC_SL1500_.jpg", "https://m.media-amazon.com/images/I/71dGAqgmMQL._AC_SL1500_.jpg"]'),
('P015', 'Utopia Bedding Fleece Blanket Queen Size Grey 300GSM Luxury Anti-Static Fuzzy Soft Microfiber Bed Blanket (90x90 Inch)', 'Bedding Fleece Blanket', 'Clothing', 18.04, 'Yes', '30', '["https://m.media-amazon.com/images/I/81ghYYh9t0L._AC_SX569_.jpg", "https://m.media-amazon.com/images/I/81GhnbzMwFL._AC_SX569_.jpg"]'),
('P016', 'Mighty Patch™ Original patch from Hero Cosmetics - Hydrocolloid Acne Pimple Patch for Covering Zits and Blemishes in Face and Skin, Vegan-friendly and Not Tested on Animals (36 Count)', 'Acne Pimple Patch', 'Personal Care', 12.99, 'Yes', '30', '["https://m.media-amazon.com/images/I/41JILztxbDL._SX679_.jpg"]'),
('P017', 'REVLON One Step Volumizer PLUS Hair Dryer and Styler | More Volume, Less Damage, and More Styling Control for Easy and Fast Salon-Style Blowouts, Plus Travel Friendly (Black)', 'Hair Styling equipment', 'Electronics', 36.05, 'Yes', '60', '["https://m.media-amazon.com/images/I/61jFEM8k2dL._AC_SX522_.jpg", "https://m.media-amazon.com/images/I/712-29-TO+L._AC_SL1500_.jpg"]'),
('P018', 'Maybelline Super Stay Matte Ink Liquid Lipstick Makeup, Long Lasting High Impact Color, Up to 16H Wear, Seductress, Light Rosey Nude, 1 Count', 'Liquid Lipstick Makeup', 'Personal Care', 5.34, 'Yes', '30', '["https://m.media-amazon.com/images/I/51rAjHLYHSL._SY606_.jpg"]'),
('P019', 'Harry\'s Razor for Men - Razor Handle and Razor Blade Cartridge - Shaving Gift Set for Him - Orange', 'Razor for Men', 'Personal Care', 7.99, 'Yes', '30', '["https://m.media-amazon.com/images/I/613WyYV-BSL._SX679_.jpg", "https://m.media-amazon.com/images/I/61osRIgf4xL._SX679_.jpg"]'),
('P020', 'Kraft Easy Mac Original Mac & Cheese Macaroni and Cheese Dinner Microwavable Dinner, 18 ct Packets', 'Mac and Cheese', 'Food', 6.98, 'Yes', '30', '["https://m.media-amazon.com/images/I/715kw5O-11L._SX569_.jpg"]');
INSERT INTO Product (ProductID, ProductName, ProductDescription, ProductCategory, ProductPrice, ReturnEligible, RefundEligibility, ProductImages) VALUES
('P021', 'Maruchan Ramen Chicken, Instant Ramen Noodles, Ready to Eat Meals, 3 Oz, 24 Count', 'Noodles', 'Food', 7.20, 'Yes', '30', '["https://m.media-amazon.com/images/I/81GfI-ftDYL._SX569_.jpg"]'),
('P022', 'Baked, Lay''s Original Potato Crisps, 0.875 Ounce (Pack of 60)', 'Chips', 'Food', 42.99, 'Yes', '30', '["https://m.media-amazon.com/images/I/813xqlCcX6S._SX569_.jpg", "https://m.media-amazon.com/images/I/817mRVe3ZJS._SX569_.jpg"]'),
('P023', 'Lays Wafers Magic Masala 52g Pack, India', 'Chips', 'Food', 5.99, 'Yes', '30', '["https://m.media-amazon.com/images/I/71HyeSkXm0L._SX569_.jpg", "https://m.media-amazon.com/images/I/51Y+MhEGwWL._SX38_SY50_CR,0,0,38,50_.jpg"]'),
('P024', 'TWIX Bulk Chocolate Candy Individually Wrapped - Full Size, Caramel Chocolate Cookie Candy Bar, 36-Count Box', 'Chocolate Candy', 'Food', 39.97, 'Yes', '30', '["https://m.media-amazon.com/images/I/41aMZ-x3ZOL._SX300_SY300_QL70_FMwebp_.jpg"]'),
('P025', 'Tang Orange Sweetened Powdered Drink Mix 1 Count 20 oz Canister', 'Powdered Drink Mix', 'Food', 3.84, 'Yes', '30', '["https://m.media-amazon.com/images/I/81aTePuzlEL._SX679_.jpg", "https://m.media-amazon.com/images/I/81+3eUFqIEL._SL1500_.jpg", "https://m.media-amazon.com/images/I/81TtUsXDiuL._SL1500_.jpg"]'),
('P026', 'LENOVO IdeaPad 1 Laptop, 15.6” FHD Display, Intel Celeron N4500 Processor, 20GB RAM, 1TB SSD, SD Card Reader, Numeric Keypad, HDMI, Wi-Fi 6, Windows 11 Home, 1 Year Office 365, Grey', 'Laptop', 'Electronics', 331.55, 'Yes', '60', '["https://m.media-amazon.com/images/I/71496nJIhVL._AC_SX425_.jpg", "https://m.media-amazon.com/images/I/81vubob7tjL._AC_SX425_.jpg", "https://m.media-amazon.com/images/I/81XOWHTTGLL._AC_SX425_.jpg"]'),
('P027', 'Seagate Portable 2TB External Hard Drive HDD — USB 3.0 for PC, Mac, PlayStation, & Xbox -1-Year Rescue Service (STGX2000400)', '2TB External Hard Drive HDD', 'Electronics', 79.99, 'Yes', '60', '["https://m.media-amazon.com/images/I/41KH-bTKcKL._AC_SX679_.jpg", "https://m.media-amazon.com/images/I/315IIebV7OL._AC_SX679_.jpg", "https://m.media-amazon.com/images/I/41vOPgZPlhL._AC_SX679_.jpg", "https://m.media-amazon.com/images/I/61QZ0+uOyRL._AC_SX679_.jpg"]'),
('P028', 'Xbox Core Wireless Gaming Controller – Velocity Green Series X|S, One, Windows PC, Android, and iOS', 'Wireless Gaming Controller', 'Electronics', 45.49, 'Yes', '60', '["https://m.media-amazon.com/images/I/71gFBUbZTAL._SX425_.jpg", "https://m.media-amazon.com/images/I/71t+hhcWmHL._SX425_.jpg", "https://m.media-amazon.com/images/I/71FXgOjx52L._SX425_.jpg", "https://m.media-amazon.com/images/I/61ud-4Wg7BL._SX425_.jpg", "https://m.media-amazon.com/images/I/71EpUdSdbrL._SX425_.jpg", "https://m.media-amazon.com/images/I/41TJLGagL4L._SX38_SY50_CR,0,0,38,50_.jpg"]'),
('P029', 'PlayStation DualSense Edge Wireless Controller', 'Wireless Gaming Controller', 'Electronics', 199, 'Yes', '60', '["https://m.media-amazon.com/images/I/516PcdpdYRL._SX522_.jpg", "https://m.media-amazon.com/images/I/61hhSbfrdtL._SX522_.jpg", "https://m.media-amazon.com/images/I/61SNkpvkqSL._SX522_.jpg", "https://m.media-amazon.com/images/I/61St9EpehYL._SX522_.jpg", "https://m.media-amazon.com/images/I/61Byebq9oML._SX522_.jpg", "https://m.media-amazon.com/images/I/51hWQouxKWL._SX522_.jpg"]'),
('P030', 'Kasa Indoor Pan/Tilt Smart Security Camera, 1080p HD Dog-Camera,2.4GHz with Night Vision,Motion Detection for Baby and Pet Monitor, Cloud & SD Card Storage, Works with Alexa& Google Home (EC70), White', 'Security Camera', 'Electronics', 19.91, 'Yes', '60', '["https://m.media-amazon.com/images/I/51oao7xTT8L._AC_SX425_.jpg", "https://m.media-amazon.com/images/I/51qbqxOEsUL._AC_SX425_.jpg"]');
INSERT INTO Product (ProductID, ProductName, ProductDescription, ProductCategory, ProductPrice, ReturnEligible, RefundEligibility, ProductImages) VALUES
('P031', 'Amazon Basics Micro SDXC Memory Card with Full Size Adapter, A2, U3, Read Speed up to 100 MB/s, 128 GB, Black', 'Memory Card', 'Electronics', 11.99, 'Yes', '60', '["https://m.media-amazon.com/images/I/61DwejyTGkL._AC_SX522_.jpg"]'),
('P032', 'Hanes Men''s EcoSmart Fleece, Pullover Crewneck Sweatshirt, 1 or 2 Pack', 'Crewneck Sweatshirt', 'Clothing', 7.15, 'Yes', '30', '["https://m.media-amazon.com/images/I/81D+bCgn8hL._AC_SX679_.jpg", "https://m.media-amazon.com/images/I/81gtlYtDElL._AC_SX679_.jpg", "https://m.media-amazon.com/images/I/71TNJRvJ4hL._AC_SX679_.jpg", "https://m.media-amazon.com/images/I/71Bfqfr+29L._AC_SX679_.jpg"]'),
('P033', 'The Children''s Place Girls'' Wide Leg Denim Jeans', 'Denim Jeans', 'Clothing', 22, 'Yes', '30', '["https://m.media-amazon.com/images/I/81zNh5pXh7L._AC_SX569_.jpg", "https://m.media-amazon.com/images/I/81vj6wCB3OL._AC_SX569_.jpg", "https://m.media-amazon.com/images/I/91UqPlBzDAL._AC_SX569_.jpg"]'),
('P034', 'Urban CoCo Women''s Basic Versatile Stretchy Flared Casual Mini Skater Skirt', 'Casual Mini Skater Skirt', 'Clothing', 14.38, 'Yes', '30', '["https://m.media-amazon.com/images/I/61fIzCQod0L._AC_SX679_.jpg", "https://m.media-amazon.com/images/I/61Z4-dv-fzL._AC_SX522_.jpg"]'),
('P035', 'Amazon Echo Dot (newest model), Vibrant sounding Alexa speaker, Great for bedrooms, dining rooms and offices, Charcoal', 'Alexa speaker', 'Electronics', 49.99, 'Yes', '60', '["https://m.media-amazon.com/images/I/514+cOjHgYL._AC_US40_.jpg", "https://m.media-amazon.com/images/I/71yRY8YlAbL._AC_SX425_.jpg", "https://m.media-amazon.com/images/I/61E80QtGeCL._AC_SX425_.jpg"]'),
('P036', 'TOSHIBA EM131A5C-BS Countertop Microwave Ovens 1.2 Cu Ft, 12.4" Removable Turntable Smart Humidity Sensor 12 Auto Menus Mute Function ECO Mode Easy Clean Interior Black Color 1100W', 'Microwave Ovens', 'Appliances', 134, 'Yes', '60', '["https://m.media-amazon.com/images/I/61moUe+FENL._AC_SX569_.jpg", "https://m.media-amazon.com/images/I/71Uh+IjnhbL._AC_SL1500_.jpg", "https://m.media-amazon.com/images/I/81QczV467NL._AC_SL1500_.jpg"]'),
('P037', 'Magic Bullet Blender, Small, Silver, 11 Piece Set', 'Bullet Blender', 'Appliances', 40, 'Yes', '60', '["https://m.media-amazon.com/images/I/61CX+M5vkgL._AC_SX569_.jpg", "https://m.media-amazon.com/images/I/71fXIcEaM6L._AC_SX569_.jpg"]'),
('P038', 'Aroma Housewares Aroma 6-cup (cooked) 1.5 Qt. One Touch Rice Cooker, White (ARC-363NG), 6 cup cooked/ 3 cup uncook/ 1.5 Qt.', 'Rice Cooker', 'Appliances', 20, 'Yes', '60', '["https://m.media-amazon.com/images/I/31EZ-jssQRL._AC_US100_.jpg"]'),
('P039', 'Hamilton Beach Food Processor & Vegetable Chopper for Slicing, Shredding, Mincing, and Puree, 10 Cups + Easy Clean Bowl Scraper, Black and Stainless Steel (70730)', 'Food Processor & Vegetable Chopper', 'Appliances', 45, 'Yes', '60', '["https://m.media-amazon.com/images/I/41V79SscRQL._AC_US100_.jpg", "https://m.media-amazon.com/images/I/71uvtApZ8bL._AC_SL1500_.jpg"]'),
('P040', 'Cuisinart 9-Inch Round Cake Pan, Chef''s Classic Nonstick Bakeware, Silver, AMB-9RCK', 'Round Cake Pan', 'Kitchen utensils', 45, 'Yes', '30', '["https://m.media-amazon.com/images/I/41o19m21iBL._AC_SX569_.jpg", "https://m.media-amazon.com/images/I/51qpNfd+apL._AC_SX569_.jpg", "https://m.media-amazon.com/images/I/81nGWvPTtVL._AC_SX569_.jpg"]');
INSERT INTO Product (ProductID, ProductName, ProductDescription, ProductCategory, ProductPrice, ReturnEligible, RefundEligibility, ProductImages) VALUES
('P041', 'LEVOIT Smart Humidifiers for Bedroom Large Room Home,(6L) Cool Mist Top Fill Essential Oil Diffuser for Baby & Plants,Smart App & Voice Control, Rapid Humidification & Auto Mode-Quiet Sleep Mode, Gray', 'Smart Humidifiers', 'Electronics', 80, 'Yes', '60', '["https://m.media-amazon.com/images/I/71YxUFC4ZlL._AC_SX569_.jpg", "https://m.media-amazon.com/images/I/41XFdKJPptL._AC_.jpg", "https://m.media-amazon.com/images/I/71yW4FOcAML._AC_SL1500_.jpg"]'),
('P042', 'The Let Them Theory: A Life-Changing Tool That Millions of People Can''t Stop Talking About', 'Original Book', 'Books', 18, 'Yes', '10', '["https://m.media-amazon.com/images/I/91ZVf3kNrcL._SY385_.jpg"]'),
('P043', 'Amazon Basics 14-Piece High Carbon Stainless Steel Kitchen Knife Set with Sharpener and Pinewood Block, Black', 'Knife Set', 'Kitchen Utensils', 26.99, 'Yes', '30', '["https://m.media-amazon.com/images/I/810IjwSOWZL._AC_SY879_.jpg", "https://m.media-amazon.com/images/I/718J8nUNveL._AC_SY879_.jpg", "https://m.media-amazon.com/images/I/71VkKj29ScL._AC_SY879_.jpg"]'),
('P044', 'Bamboo Cutting Boards for Kitchen [Set of 3] Wood Cutting Board for Chopping Meat, Vegetables, Fruits, Cheese, Knife Friendly Serving Tray with Handles', 'Cutting Boards', 'Kitchen Utensils', 11.36, 'Yes', '30', '["https://m.media-amazon.com/images/I/81gLwPfpWbL._AC_SX569_.jpg", "https://m.media-amazon.com/images/I/81DmMQFXTYL._AC_SX569_.jpg", "https://m.media-amazon.com/images/I/71E-e0A7nnL._AC_SX569_.jpg"]'),
('P045', 'Homall Bar Stools Modern PU Leather Adjustable Swivel Barstools, Armless Hydraulic Kitchen Counter Bar Stool Extra Height Square Island Barstool with Back Set of 2 (Leather, Black)', 'Bar Stool', 'Furniture', 66.49, 'Yes', '30', '["https://m.media-amazon.com/images/I/61vjgfkBi1L._AC_SX522_.jpg", "https://m.media-amazon.com/images/I/71OEPWke1tL._AC_SX522_.jpg"]'),
('P046', 'Rubbermaid Brilliance 16-Cup Airtight Food Storage Container with Lid, Clear/Grey - optimal for pantry organization, flour, sugar, and food storage', 'Food Storage Container with Lid', 'Kitchen utensils', 18.39, 'Yes', '30', '["https://m.media-amazon.com/images/I/81SnUAn4umL._AC_SX522_.jpg", "https://m.media-amazon.com/images/I/61sR5CVVkGL._AC_SX522_.jpg"]'),
('P047', 'Zuutii Rice Storage Container,Food Container, Dry Food Storage, Pet Food Dispenser, 6.9Qt Large Storage Bin with Lid,Silicone Ring & Moisture Proof, for Grain Cereal Soybean Corn, Black', 'Rice Storage Container', 'Kitchen utensils', 26.99, 'Yes', '30', '["https://m.media-amazon.com/images/I/31T+oXXLQuL._AC_US100_.jpg", "https://m.media-amazon.com/images/I/51lHiINXRAL._AC_SX522_.jpg", "https://m.media-amazon.com/images/I/61rNp75NZNL._AC_SX522_.jpg", "https://m.media-amazon.com/images/I/61XADwuz4CL._AC_SX522_.jpg"]'),
('P048', 'San Diego Hat Company Men''s Embroidered Beanie Hat - One Size Fits Most - Brown with Gold Thread (Brown)', 'Beanie Hat', 'Clothing', 24, 'Yes', '60', '["https://m.media-amazon.com/images/I/81OoA31UbQL._SY500_.jpg", "https://m.media-amazon.com/images/I/71FwOnhfe1L._SY800_.jpg"]'),
('P049', 'Boelter Brands MLB unisex Relief Sculpted Mug', 'Mug', 'Glassware items', 15, 'Yes', '60', '["https://m.media-amazon.com/images/I/610kHvDDLCL._AC_SX679_.jpg"]'),
('P050', 'adidas Select Basketball Crew Socks (1 pair) for team sports, boys girls men women', 'Basketball Crew Socks', 'Clothing', 12, 'Yes', '60', '["https://m.media-amazon.com/images/I/810wEkDprTL._AC_SX679_.jpg", "https://m.media-amazon.com/images/I/81odyZy7l2L._AC_SX679_.jpg", "https://m.media-amazon.com/images/I/71cj7XCQZdL._AC_SX679_.jpg", "https://m.media-amazon.com/images/I/813FO2eooUL._AC_SX679_.jpg"]');

#######################
###populating orders table
INSERT INTO `Order` (OrderID, CustomerID, ProductID, OrderQty, OrderDate, DeliveryDate) VALUES
('ORD001', 1, 'P001', 1, '2025-01-10', '2025-01-15'),
('ORD002', 2, 'P002', 2, '2025-02-05', '2025-02-10'),
('ORD003', 3, 'P003', 3, '2025-03-01', '2025-03-03'),
('ORD004', 4, 'P004', 1, '2025-01-20', '2025-01-26'),
('ORD005', 5, 'P005', 1, '2025-02-12', '2025-02-18'),
('ORD006', 6, 'P006', 2, '2025-01-03', '2025-01-07'),
('ORD007', 7, 'P007', 1, '2025-02-18', '2025-02-22'),
('ORD008', 8, 'P008', 1, '2025-01-22', '2025-01-28'),
('ORD009', 9, 'P009', 1, '2025-02-10', '2025-02-15'),
('ORD010', 10, 'P010', 2, '2025-01-15', '2025-01-20');
INSERT INTO `Order` (OrderID, CustomerID, ProductID, OrderQty, OrderDate, DeliveryDate) VALUES
('ORD011', 2, 'P012', 2, '2025-02-01', '2025-02-05'),
('ORD012', 4, 'P015', 1, '2025-01-08', '2025-01-14'),
('ORD013', 6, 'P018', 3, '2025-01-20', '2025-01-23'),
('ORD014', 8, 'P021', 2, '2025-02-12', '2025-02-16'),
('ORD015', 10, 'P024', 1, '2025-01-15', '2025-01-18'),
('ORD016', 3, 'P026', 1, '2025-02-22', '2025-02-28'),
('ORD017', 5, 'P029', 2, '2025-01-25', '2025-01-30'),
('ORD018', 7, 'P032', 1, '2025-01-03', '2025-01-09'),
('ORD019', 9, 'P035', 2, '2025-02-18', '2025-02-22'),
('ORD020', 1, 'P038', 1, '2025-03-01', '2025-03-05');
INSERT INTO `Order` (OrderID, CustomerID, ProductID, OrderQty, OrderDate, DeliveryDate) VALUES
('ORD021', 5, 'P011', 1, '2025-01-30', '2025-02-04'),
('ORD022', 7, 'P013', 2, '2025-01-11', '2025-01-16'),
('ORD023', 9, 'P017', 1, '2025-02-28', '2025-03-03'),
('ORD024', 1, 'P020', 3, '2025-01-07', '2025-01-12'),
('ORD025', 3, 'P023', 2, '2025-02-17', '2025-02-22'),
('ORD026', 5, 'P028', 1, '2025-01-24', '2025-01-29'),
('ORD027', 7, 'P030', 1, '2025-02-08', '2025-02-14'),
('ORD028', 9, 'P033', 2, '2025-01-16', '2025-01-21'),
('ORD029', 2, 'P036', 1, '2025-02-15', '2025-02-19'),
('ORD030', 4, 'P040', 1, '2025-01-18', '2025-01-24');
INSERT INTO `Order` (OrderID, CustomerID, ProductID, OrderQty, OrderDate, DeliveryDate) VALUES
('ORD031', 8, 'P014', 1, '2025-02-25', '2025-03-03'),
('ORD032', 10, 'P016', 2, '2025-01-29', '2025-02-03'),
('ORD033', 1, 'P018', 3, '2025-02-11', '2025-02-17'),
('ORD034', 3, 'P022', 1, '2025-01-12', '2025-01-18'),
('ORD035', 5, 'P025', 1, '2025-02-08', '2025-02-13'),
('ORD036', 7, 'P027', 1, '2025-01-05', '2025-01-09'),
('ORD037', 9, 'P031', 2, '2025-02-20', '2025-02-25'),
('ORD038', 2, 'P034', 1, '2025-01-22', '2025-01-26'),
('ORD039', 4, 'P039', 1, '2025-03-01', '2025-03-06'),
('ORD040', 6, 'P042', 2, '2025-01-17', '2025-01-22');
INSERT INTO `Order` (OrderID, CustomerID, ProductID, OrderQty, OrderDate, DeliveryDate) VALUES
('ORD041', 10, 'P043', 1, '2025-01-30', '2025-02-04'),
('ORD042', 8, 'P045', 2, '2025-02-03', '2025-02-08'),
('ORD043', 6, 'P047', 1, '2025-01-08', '2025-01-12'),
('ORD044', 4, 'P049', 3, '2025-01-15', '2025-01-21'),
('ORD045', 2, 'P044', 2, '2025-02-16', '2025-02-22'),
('ORD046', 1, 'P046', 1, '2025-01-25', '2025-01-31'),
('ORD047', 3, 'P048', 2, '2025-02-18', '2025-02-24'),
('ORD048', 5, 'P050', 1, '2025-02-28', '2025-03-04'),
('ORD049', 7, 'P041', 1, '2025-02-12', '2025-02-18'),
('ORD050', 9, 'P037', 2, '2025-01-10', '2025-01-16');



