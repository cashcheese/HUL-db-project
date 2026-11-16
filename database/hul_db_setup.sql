-- ============================================
-- HUL Supply Chain DBMS - Setup Script
-- Run this ONCE to create the database.
-- Then run hul_supply_chain_data_2023.sql,
--           hul_supply_chain_data_2024.sql,
--           hul_supply_chain_data_2025.sql
-- in that order to insert historical data.
-- ============================================

DROP DATABASE IF EXISTS hul_db;
CREATE DATABASE hul_db;
USE hul_db;

-- ============================================
-- 1. MASTER TABLES
-- ============================================

CREATE TABLE Brand (
    Brand_ID INT PRIMARY KEY,
    Name VARCHAR(100) NOT NULL,
    Category VARCHAR(100)
);

CREATE TABLE Product (
    Product_ID INT PRIMARY KEY,
    Brand_ID INT,
    Name VARCHAR(200) NOT NULL,
    Unit VARCHAR(50),
    Category VARCHAR(100),
    FOREIGN KEY (Brand_ID) REFERENCES Brand(Brand_ID)
);

CREATE TABLE RawMaterial (
    Product_ID INT PRIMARY KEY,
    Supplier_Specs TEXT,
    ShelfLife INT,
    FOREIGN KEY (Product_ID) REFERENCES Product(Product_ID),
    CHECK (ShelfLife > 0)
);

CREATE TABLE FinishedGood (
    Product_ID INT PRIMARY KEY,
    MRP DECIMAL(10,2),
    PackagingType VARCHAR(100),
    ExpiryRule VARCHAR(100),
    ShelfLife INT,
    FOREIGN KEY (Product_ID) REFERENCES Product(Product_ID),
    CHECK (MRP > 0 AND ShelfLife > 0)
);

CREATE TABLE Supplier (
    Supplier_ID INT PRIMARY KEY,
    Name VARCHAR(200),
    Address TEXT,
    Region VARCHAR(100),
    Rating INT,
    CHECK (Rating BETWEEN 1 AND 5)
);

CREATE TABLE SupplierContact (
    Supplier_ID INT,
    Contact VARCHAR(50),
    PRIMARY KEY (Supplier_ID, Contact),
    FOREIGN KEY (Supplier_ID) REFERENCES Supplier(Supplier_ID) ON DELETE CASCADE
);

CREATE TABLE SupplierEmail (
    Supplier_ID INT,
    Email VARCHAR(100),
    PRIMARY KEY (Supplier_ID, Email),
    FOREIGN KEY (Supplier_ID) REFERENCES Supplier(Supplier_ID) ON DELETE CASCADE
);

CREATE TABLE Supplies (
    Supplier_ID INT NOT NULL,
    Product_ID INT NOT NULL,
    ContractPrice DECIMAL(12,4),
    MOQ DECIMAL(10,2),
    LeadTime INT,
    PRIMARY KEY (Supplier_ID, Product_ID),
    FOREIGN KEY (Supplier_ID) REFERENCES Supplier(Supplier_ID),
    FOREIGN KEY (Product_ID) REFERENCES RawMaterial(Product_ID),
    CHECK (ContractPrice >= 0 AND MOQ >= 0 AND LeadTime >= 0)
);

CREATE TABLE BillOfItems (
    FinishedGood_ID INT,
    RawMaterial_ID INT,
    QuantityRequired DECIMAL(10,2) NOT NULL CHECK (QuantityRequired > 0),
    PRIMARY KEY (FinishedGood_ID, RawMaterial_ID),
    FOREIGN KEY (FinishedGood_ID) REFERENCES FinishedGood(Product_ID),
    FOREIGN KEY (RawMaterial_ID) REFERENCES RawMaterial(Product_ID)
);

-- ============================================
-- 2. PROCUREMENT
-- ============================================

CREATE TABLE PurchaseOrder (
    PO_ID INT PRIMARY KEY AUTO_INCREMENT,
    Supplier_ID INT,
    OrderDate DATE,
    ExpectedDelivery DATE,
    Status VARCHAR(50),
    FOREIGN KEY (Supplier_ID) REFERENCES Supplier(Supplier_ID),
    CHECK (ExpectedDelivery >= OrderDate)
);

CREATE TABLE POLineItem (
    PO_ID INT,
    Product_ID INT,
    Quantity INT,
    UnitPrice DECIMAL(10,2),
    PRIMARY KEY (PO_ID, Product_ID),
    FOREIGN KEY (PO_ID) REFERENCES PurchaseOrder(PO_ID),
    FOREIGN KEY (Product_ID) REFERENCES RawMaterial(Product_ID),
    CHECK (Quantity > 0 AND UnitPrice >= 0)
);

CREATE TABLE GoodsReceipt (
    GRN_ID INT PRIMARY KEY,
    PO_ID INT,
    Date DATE,
    ReceivedBy VARCHAR(100),
    FOREIGN KEY (PO_ID) REFERENCES PurchaseOrder(PO_ID)
);

-- ============================================
-- 3. MANUFACTURING
-- ============================================

CREATE TABLE Factory (
    Factory_ID INT PRIMARY KEY,
    Name VARCHAR(200),
    Location VARCHAR(200),
    Type VARCHAR(100)
);

CREATE TABLE Batch (
    Batch_ID INT PRIMARY KEY,
    Product_ID INT,
    Mfg_Date DATE,
    ExpiryDate DATE,
    TotalQty INT,
    AvailableQty INT,
    FOREIGN KEY (Product_ID) REFERENCES Product(Product_ID),
    CHECK (AvailableQty >= 0 AND AvailableQty <= TotalQty)
);

CREATE TABLE GRLineItem (
    GRN_ID INT NOT NULL,
    Batch_ID INT NOT NULL,
    Product_ID INT NOT NULL,
    Qty_Received DECIMAL(12,3) NOT NULL,
    QC_Status VARCHAR(50),
    PRIMARY KEY (GRN_ID, Product_ID, Batch_ID),
    FOREIGN KEY (GRN_ID) REFERENCES GoodsReceipt(GRN_ID),
    FOREIGN KEY (Batch_ID) REFERENCES Batch(Batch_ID),
    FOREIGN KEY (Product_ID) REFERENCES RawMaterial(Product_ID)
);

CREATE TABLE ManufacturingOrder (
    MO_ID INT PRIMARY KEY,
    Factory_ID INT,
    Date DATE,
    Qty INT,
    FOREIGN KEY (Factory_ID) REFERENCES Factory(Factory_ID)
);

CREATE TABLE ManufacturingOrderInput (
    MO_ID INT,
    Batch_ID INT,
    Qty_Consumed DECIMAL(12,3),
    PRIMARY KEY (MO_ID, Batch_ID),
    FOREIGN KEY (MO_ID) REFERENCES ManufacturingOrder(MO_ID),
    FOREIGN KEY (Batch_ID) REFERENCES Batch(Batch_ID)
);

CREATE TABLE ManufacturingOrderOutput (
    MO_ID INT,
    Batch_ID INT,
    Qty_Produced DECIMAL(12,3),
    PRIMARY KEY (MO_ID, Batch_ID),
    FOREIGN KEY (MO_ID) REFERENCES ManufacturingOrder(MO_ID),
    FOREIGN KEY (Batch_ID) REFERENCES Batch(Batch_ID)
);

-- ============================================
-- 4. INVENTORY & WAREHOUSE
-- ============================================

CREATE TABLE Warehouse (
    Warehouse_ID INT PRIMARY KEY,
    Name VARCHAR(200),
    Location VARCHAR(200),
    Type VARCHAR(100)
);

CREATE TABLE Inventory (
    Inventory_ID INT PRIMARY KEY,
    Batch_ID INT NOT NULL,
    Warehouse_ID INT NOT NULL,
    Quantity INT NOT NULL,
    LastUpdated DATE,
    FOREIGN KEY (Batch_ID) REFERENCES Batch(Batch_ID),
    FOREIGN KEY (Warehouse_ID) REFERENCES Warehouse(Warehouse_ID),
    CHECK (Quantity >= 0)
);

-- ============================================
-- 5. CUSTOMER & CHANNEL
-- ============================================

CREATE TABLE Channel (
    Channel_ID INT PRIMARY KEY,
    Channel_Name VARCHAR(100),
    Channel_Mgr VARCHAR(100),
    Distribution_mode VARCHAR(50),
    Channel_Pay_Terms VARCHAR(100)
);

CREATE TABLE Customer (
    Cust_ID INT PRIMARY KEY,
    Cust_Name VARCHAR(200),
    ContractTerms VARCHAR(200),
    Cust_limits VARCHAR(100),
    Cust_location VARCHAR(200)
);

CREATE TABLE Customer_Channel (
    Cust_ID INT,
    Channel_ID INT,
    PRIMARY KEY (Cust_ID, Channel_ID),
    FOREIGN KEY (Cust_ID) REFERENCES Customer(Cust_ID) ON DELETE CASCADE,
    FOREIGN KEY (Channel_ID) REFERENCES Channel(Channel_ID)
);

-- ============================================
-- 6. DISTRIBUTION ORDERS
-- ============================================

CREATE TABLE DistributionOrder (
    Dist_ID INT PRIMARY KEY,
    Cust_ID INT,
    Order_Date DATE,
    Delivery_Date DATE,
    Status VARCHAR(50),
    Payment_Terms VARCHAR(100),
    FOREIGN KEY (Cust_ID) REFERENCES Customer(Cust_ID),
    CHECK (Delivery_Date >= Order_Date)
);

CREATE TABLE DistributionOrderLine (
    Dist_ID INT,
    Inventory_ID INT,
    Qty_Ordered INT,
    Qty_Dispatched INT,
    Price_Per_Unit DECIMAL(10,2),
    PRIMARY KEY (Dist_ID, Inventory_ID),
    FOREIGN KEY (Dist_ID) REFERENCES DistributionOrder(Dist_ID),
    FOREIGN KEY (Inventory_ID) REFERENCES Inventory(Inventory_ID),
    CHECK (Qty_Ordered > 0 AND Qty_Dispatched >= 0 AND Price_Per_Unit >= 0)
);

-- ============================================
-- 7. SHIPMENT
-- ============================================

CREATE TABLE Shipment (
    Shipment_ID INT PRIMARY KEY AUTO_INCREMENT,
    Cust_ID INT,
    Carrier VARCHAR(100),
    Transport_Mode VARCHAR(100),
    Dispatch_Date DATE,
    Arrival_Date DATE,
    Shipment_Status VARCHAR(50),
    FOREIGN KEY (Cust_ID) REFERENCES Customer(Cust_ID),
    CHECK (Arrival_Date >= Dispatch_Date)
);

CREATE TABLE ShipmentDetails (
    Shipment_ID INT,
    Dist_ID INT,
    PRIMARY KEY (Shipment_ID, Dist_ID),
    FOREIGN KEY (Shipment_ID) REFERENCES Shipment(Shipment_ID),
    FOREIGN KEY (Dist_ID) REFERENCES DistributionOrder(Dist_ID)
);

-- ============================================
-- 8. INVOICE & PAYMENT
-- ============================================

CREATE TABLE Invoice (
    Invoice_ID INT PRIMARY KEY AUTO_INCREMENT,
    Dist_ID INT,
    Invoice_Date DATE,
    Amount DECIMAL(12,2),
    Discount DECIMAL(10,2),
    Tax DECIMAL(10,2),
    Final_Amount DECIMAL(12,2),
    Status VARCHAR(50) NOT NULL DEFAULT 'Unpaid'
        CHECK (Status IN ('Unpaid', 'Partially Paid', 'Paid', 'Canceled')),
    FOREIGN KEY (Dist_ID) REFERENCES DistributionOrder(Dist_ID),
    CHECK (Amount >= 0 AND Discount >= 0 AND Tax >= 0 AND Final_Amount >= 0)
);

CREATE TABLE Payment (
    Pay_ID INT PRIMARY KEY AUTO_INCREMENT,
    Invoice_ID INT,
    Cust_ID INT,
    Pay_Date DATE,
    Pay_Method VARCHAR(50),
    Amount_Paid DECIMAL(12,2),
    Status VARCHAR(50),
    Trans_Ref VARCHAR(100),
    FOREIGN KEY (Invoice_ID) REFERENCES Invoice(Invoice_ID) ON DELETE CASCADE,
    FOREIGN KEY (Cust_ID) REFERENCES Customer(Cust_ID),
    CHECK (Amount_Paid > 0)
);

-- ============================================
-- 9. SEED DATA
-- ============================================

INSERT INTO Brand VALUES
(1, 'Bru', 'Beverages'),
(2, 'Knorr', 'Foods'),
(3, 'Surf Excel', 'Home Care');

INSERT INTO Supplier VALUES
(101, 'Karnataka Coffee Growers Co-op', 'Chikmagalur, Karnataka', 'South', 5),
(102, 'Deccan Agri Ingredients', 'Hyderabad, Telangana', 'South', 4),
(103, 'Gujarat Chemical Corporation', 'Vapi, Gujarat', 'West', 5);

INSERT INTO Customer VALUES
(501, 'DMart - Whitefield', 'Annual Supply Agreement', '5000000', 'Bengaluru, Karnataka'),
(502, 'Sharma General Store', 'Standard Trade Terms', '50000', 'Jayanagar, Bengaluru'),
(503, 'Taj MG Road, Bengaluru', 'Institutional HORECA Contract', '300000', 'Bengaluru, Karnataka');

INSERT INTO Channel VALUES
(1, 'Modern Trade', NULL, 'Direct to DC', NULL),
(2, 'General Trade', NULL, 'Distributor', NULL),
(3, 'Institutional Sales', NULL, 'Direct Supply', NULL);

INSERT INTO Factory VALUES (1, 'HUL Mega Factory', 'Hosur, Tamil Nadu', 'Multi-Product');
INSERT INTO Warehouse VALUES (1, 'HUL Regional DC', 'Bengaluru, Karnataka', 'Distribution Center');

INSERT INTO Product VALUES
(1001, 1, 'Coffee Beans - Grade A Arabica', 'kg', 'Raw Material'),
(2001, 1, 'Bru Instant Coffee 50g Jar', 'jar', 'Finished Good'),
(1002, 2, 'Dehydrated Tomato Powder', 'kg', 'Raw Material'),
(2002, 2, 'Knorr Classic Thick Tomato Soup 50g', 'packet', 'Finished Good'),
(1003, 3, 'Surfactant & Soda Ash Blend', 'kg', 'Raw Material'),
(2003, 3, 'Surf Excel Matic Top Load 1kg', 'box', 'Finished Good');

INSERT INTO RawMaterial (Product_ID, ShelfLife) VALUES (1001, 365), (1002, 180), (1003, 730);

INSERT INTO FinishedGood (Product_ID, MRP, PackagingType, ShelfLife) VALUES
(2001, 150.00, 'Glass Jar', 365),
(2002, 60.00, 'Sachet', 270),
(2003, 240.00, 'Cardboard Box', 730);

INSERT INTO Supplies (Supplier_ID, Product_ID, ContractPrice) VALUES
(101, 1001, 400.00),
(102, 1002, 250.00),
(103, 1003, 80.00);

INSERT INTO BillOfItems VALUES
(2001, 1001, 0.050),
(2002, 1002, 0.020),
(2003, 1003, 0.950);

INSERT INTO Customer_Channel VALUES (501, 1), (502, 2), (503, 3);

INSERT INTO SupplierContact VALUES
(101, '080-123456'), (102, '040-654321'), (103, '0260-222333');

INSERT INTO SupplierEmail VALUES
(101, 'info@karnatakacoffee.com'),
(102, 'sales@deccanagri.in'),
(103, 'orders@gujchem.com');

-- ============================================
-- 10. PROCUREMENT & MANUFACTURING SEED DATA
-- ============================================

INSERT INTO PurchaseOrder (PO_ID, Supplier_ID, OrderDate, ExpectedDelivery, Status) VALUES
(9001, 101, '2025-01-15', '2025-01-20', 'Delivered'),
(9002, 102, '2025-01-18', '2025-01-23', 'Delivered'),
(9003, 103, '2025-01-20', '2025-01-26', 'Delivered');

INSERT INTO POLineItem VALUES
(9001, 1001, 1000, 400.00),
(9002, 1002, 800, 250.00),
(9003, 1003, 1200, 80.00);

INSERT INTO GoodsReceipt VALUES
(8001, 9001, '2025-01-21', 'Anita'),
(8002, 9002, '2025-01-25', 'Ravi'),
(8003, 9003, '2025-01-27', 'Meena');

-- Raw material batches (AvailableQty already reflects MO consumption)
INSERT INTO Batch VALUES
(7001, 1001, '2025-01-20', '2026-01-20', 1000, 975),
(7002, 1002, '2025-01-24', '2025-07-24', 800, 794),
(7003, 1003, '2025-01-26', '2027-01-26', 1200, 820);

INSERT INTO GRLineItem VALUES
(8001, 7001, 1001, 1000, 'Accepted'),
(8002, 7002, 1002, 800, 'Accepted'),
(8003, 7003, 1003, 1200, 'Accepted');

INSERT INTO ManufacturingOrder VALUES
(6001, 1, '2025-02-01', 500),
(6002, 1, '2025-02-05', 300),
(6003, 1, '2025-02-10', 400);

INSERT INTO ManufacturingOrderInput VALUES
(6001, 7001, 25),
(6002, 7002, 6),
(6003, 7003, 380);

-- Finished good batches
INSERT INTO Batch VALUES
(7010, 2001, '2025-02-02', '2026-02-02', 500, 400),
(7011, 2002, '2025-02-06', '2025-09-06', 300, 250),
(7012, 2003, '2025-02-12', '2027-02-12', 400, 320);

INSERT INTO ManufacturingOrderOutput VALUES
(6001, 7010, 500),
(6002, 7011, 300),
(6003, 7012, 400);

-- ============================================
-- 11. INVENTORY
-- NOTE: Before inserting synthetic historical data,
--       run the UNLOCK block below.
--       After insertion, run the RESET block.
-- ============================================

INSERT INTO Inventory VALUES
(5001, 7010, 1, 400, '2025-02-03'),
(5002, 7011, 1, 250, '2025-02-07'),
(5003, 7012, 1, 320, '2025-02-13');

-- ============================================
-- 12. DELIVERED SEED ORDERS (Live Demo Data)
-- ============================================

INSERT INTO DistributionOrder VALUES
(1, 501, '2025-02-04', '2025-02-06', 'Delivered', '30 Days Credit'),
(2, 502, '2025-02-06', '2025-02-08', 'Delivered', 'Cash on Delivery'),
(3, 503, '2025-02-08', '2025-02-10', 'Delivered', 'Immediate Payment');

INSERT INTO DistributionOrderLine VALUES
(1, 5001, 100, 100, 150.00),
(2, 5002, 50, 50, 60.00),
(3, 5003, 80, 80, 240.00);

INSERT INTO Shipment (Shipment_ID, Cust_ID, Carrier, Transport_Mode, Dispatch_Date, Arrival_Date, Shipment_Status) VALUES
(3001, 501, 'BlueDart', 'Truck', '2025-02-05', '2025-02-06', 'Delivered'),
(3002, 502, 'Delhivery', 'Truck', '2025-02-07', '2025-02-08', 'Delivered'),
(3003, 503, 'Gati', 'Truck', '2025-02-09', '2025-02-10', 'Delivered');

INSERT INTO ShipmentDetails VALUES (3001, 1), (3002, 2), (3003, 3);

INSERT INTO Invoice (Invoice_ID, Dist_ID, Invoice_Date, Amount, Discount, Tax, Final_Amount, Status) VALUES
(20001, 1, '2025-02-06', 15000.00, 500.00, 2700.00, 17200.00, 'Paid'),
(20002, 2, '2025-02-08', 3000.00, 0.00, 540.00, 3540.00, 'Paid'),
(20003, 3, '2025-02-10', 19200.00, 200.00, 3456.00, 22456.00, 'Paid');

INSERT INTO Payment (Pay_ID, Invoice_ID, Cust_ID, Pay_Date, Pay_Method, Amount_Paid, Status, Trans_Ref) VALUES
(10001, 20001, 501, '2025-02-15', 'NEFT', 17200.00, 'Completed', 'TXN123ABC'),
(10002, 20002, 502, '2025-02-16', 'Cash', 3540.00, 'Completed', 'TXN456DEF'),
(10003, 20003, 503, '2025-02-18', 'Card', 22456.00, 'Completed', 'TXN789GHI');

-- ============================================
-- 13. LIVE DEMO ORDERS (Processing / Blocked)
-- ============================================

-- Order 4: Ready to fulfill (sufficient stock)
INSERT INTO DistributionOrder VALUES
(4, 501, CURDATE(), DATE_ADD(CURDATE(), INTERVAL 2 DAY), 'Processing', '30 Days Credit');
INSERT INTO DistributionOrderLine VALUES (4, 5001, 50, 0, 150.00);

-- Order 5: Blocked (stock shortfall on Bru Coffee line)
INSERT INTO DistributionOrder VALUES
(5, 502, CURDATE(), DATE_ADD(CURDATE(), INTERVAL 2 DAY), 'Processing', 'Cash on Delivery');
INSERT INTO DistributionOrderLine VALUES (5, 5002, 100, 0, 60.00);
INSERT INTO DistributionOrderLine VALUES (5, 5001, 1000, 0, 150.00);

-- Unpaid invoice for Order 4 (demo finance panel)
INSERT INTO Invoice (Invoice_ID, Dist_ID, Invoice_Date, Amount, Discount, Tax, Final_Amount, Status)
VALUES (20004, 4, CURDATE(), 7500.00, 0, 1350.00, 8850.00, 'Unpaid');

-- ============================================
-- 14. AUTO_INCREMENT STARTING POINTS
-- ============================================

ALTER TABLE PurchaseOrder AUTO_INCREMENT = 9004;
ALTER TABLE Shipment AUTO_INCREMENT = 3005;
ALTER TABLE Invoice AUTO_INCREMENT = 20005;
ALTER TABLE Payment AUTO_INCREMENT = 10004;

-- ============================================
-- SYNTHETIC DATA INSTRUCTIONS
-- ============================================
-- Step 1: Run this file completely.
-- Step 2: Run the UNLOCK block:
--
--   UPDATE Inventory SET Quantity = 999999 WHERE Inventory_ID IN (5001, 5002, 5003);
--   UPDATE Batch SET AvailableQty = 999999 WHERE Batch_ID IN (7010, 7011, 7012);
--
-- Step 3: Run hul_supply_chain_data_2023.sql
-- Step 4: Run hul_supply_chain_data_2024.sql
-- Step 5: Run hul_supply_chain_data_2025.sql
-- Step 6: Run the RESET block:
--
--   UPDATE Inventory SET Quantity = 400 WHERE Inventory_ID = 5001;
--   UPDATE Inventory SET Quantity = 250 WHERE Inventory_ID = 5002;
--   UPDATE Inventory SET Quantity = 320 WHERE Inventory_ID = 5003;
--   UPDATE Batch SET AvailableQty = 400 WHERE Batch_ID = 7010;
--   UPDATE Batch SET AvailableQty = 250 WHERE Batch_ID = 7011;
--   UPDATE Batch SET AvailableQty = 320 WHERE Batch_ID = 7012;
--
-- Step 7: Run stored procedures, triggers, functions scripts.
-- Step 8: Run python forecasting/train.py from project root.
-- ============================================

COMMIT;