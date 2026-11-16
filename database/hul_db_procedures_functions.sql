-- ===================================================
-- HUL DB - PROCEDURES & FUNCTIONS SCRIPT (v2.1 - Optimistic)
--
-- This script adds the reusable "business logic"
-- to be called by the application.
--
-- v2.1 changes:
-- - sp_AllocateStockForOrder NOW subtracts stock.
-- - sp_CancelDistributionOrder is simplified (no stock return).
-- - NEW: sp_DeallocateStockForOrder to manually return stock.
-- ===================================================

USE hul_db;


-- ============================================
-- PART 0: DROP ALL EXISTING OBJECTS FIRST
-- ============================================
DROP FUNCTION IF EXISTS fn_GetTotalPendingOrders;
DROP FUNCTION IF EXISTS fn_GetTotalOutstandingBalance;
DROP FUNCTION IF EXISTS fn_CheckOrderStockStatus;
DROP PROCEDURE IF EXISTS sp_GetPendingOrders;
DROP PROCEDURE IF EXISTS sp_GetCustomersWithOverdueInvoices;
DROP PROCEDURE IF EXISTS sp_CreateNewPurchaseOrder;
DROP PROCEDURE IF EXISTS sp_UpdateShipmentStatus;
DROP PROCEDURE IF EXISTS sp_CancelDistributionOrder;
DROP PROCEDURE IF EXISTS sp_GetInventorySnapshot;
DROP PROCEDURE IF EXISTS sp_AllocateStockForOrder;
DROP PROCEDURE IF EXISTS sp_DeallocateStockForOrder; -- Added
DROP PROCEDURE IF EXISTS sp_GeneratePurchaseOrdersForShortfall;
DROP PROCEDURE IF EXISTS sp_GetAllRawMaterials;
DROP PROCEDURE IF EXISTS sp_GetOrderDetailsForTriage;
DROP PROCEDURE IF EXISTS sp_GetRawMaterialNeeds;
DROP PROCEDURE IF EXISTS sp_GetSuppliersForRawMaterial;
DROP PROCEDURE IF EXISTS sp_GetAllPurchaseOrders;
DROP PROCEDURE IF EXISTS sp_GetUnpaidInvoices;
DROP PROCEDURE IF EXISTS sp_RecordPayment;
DROP PROCEDURE IF EXISTS sp_GetAllPayments;

-- ============================================
-- PART 1: DASHBOARD FUNCTIONS
-- ============================================
DELIMITER $$
CREATE FUNCTION fn_GetTotalPendingOrders()
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_Total INT;
    SELECT COUNT(*) INTO v_Total FROM DistributionOrder
    WHERE Status = 'Processing'; -- Only count new, un-allocated orders
    RETURN v_Total;
END$$

CREATE FUNCTION fn_GetTotalOutstandingBalance()
RETURNS DECIMAL(12,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_TotalBalance DECIMAL(12,2);
    
    -- This new logic calculates the sum of all REMAINING balances
    SELECT COALESCE(SUM(i.Final_Amount - COALESCE(p.TotalPaid, 0)), 0)
    INTO v_TotalBalance
    FROM Invoice i
    LEFT JOIN (
        -- Subquery to get total completed payments per invoice
        SELECT Invoice_ID, SUM(Amount_Paid) AS TotalPaid
        FROM Payment
        WHERE Status = 'Completed'
        GROUP BY Invoice_ID
    ) p ON i.Invoice_ID = p.Invoice_ID
    -- Only sum invoices that are not fully paid
    WHERE i.Status IN ('Unpaid', 'Partially Paid');

    RETURN v_TotalBalance;
END$$

-- *** NEW FUNCTION (The Core Logic) ***
-- This function checks if a given Distribution Order can be fulfilled.
CREATE FUNCTION fn_CheckOrderStockStatus(p_DistID INT)
RETURNS VARCHAR(50)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_Status VARCHAR(50) DEFAULT '✅ Ready to Fulfill';
    DECLARE v_Finished INT DEFAULT 0;
    DECLARE v_InvID INT;
    DECLARE v_Qty INT;
    DECLARE v_InvStock INT;

    -- Cursor to loop through all line items for the given order
    DECLARE cur CURSOR FOR 
        SELECT Inventory_ID, Qty_Ordered 
        FROM DistributionOrderLine 
        WHERE Dist_ID = p_DistID;
        
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_Finished = 1;

    OPEN cur;
    check_loop: LOOP
        FETCH cur INTO v_InvID, v_Qty;
        IF v_Finished THEN
            LEAVE check_loop;
        END IF;

        -- Get the current stock for that specific inventory item
        SELECT Quantity INTO v_InvStock
        FROM Inventory
        WHERE Inventory_ID = v_InvID;

        -- If any item is out of stock, mark the whole order and exit
        IF v_InvStock < v_Qty THEN
            SET v_Status = '❌ Blocked (Stock Shortfall)';
            LEAVE check_loop;
        END IF;
    END LOOP;
    CLOSE cur;

    RETURN v_Status;
END$$


-- ============================================
-- PART 2: DASHBOARD PROCEDURES
-- ============================================

-- *** MODIFIED PROCEDURE ***
-- Gets pending orders AND their stock status.
CREATE PROCEDURE sp_GetPendingOrders()
BEGIN
    SELECT 
        do.Dist_ID,
        do.Order_Date,
        c.Cust_Name,
        do.Status,
        -- Call our new function to get the live stock status
        fn_CheckOrderStockStatus(do.Dist_ID) AS Stock_Status
    FROM DistributionOrder do
    JOIN Customer c ON do.Cust_ID = c.Cust_ID
    -- Show Processing AND Allocated orders in the queue
    WHERE do.Status IN ('Processing', 'Allocated - Ready to Ship') 
    ORDER BY do.Order_Date ASC;
END$$

-- Gets a snapshot of the current inventory
CREATE PROCEDURE sp_GetInventorySnapshot()
BEGIN
    SELECT 
        p.Name AS ProductName,
        i.Quantity,
        p.Unit,
        b.ExpiryDate
    FROM Inventory i
    JOIN Batch b ON i.Batch_ID = b.Batch_ID
    JOIN Product p ON b.Product_ID = p.Product_ID
    ORDER BY p.Name;
END$$

CREATE PROCEDURE sp_GetCustomersWithOverdueInvoices()
BEGIN
    SELECT Cust_Name, Cust_location
    FROM Customer
    WHERE Cust_ID IN (
        SELECT Cust_ID FROM Invoice
        WHERE Status IN ('Unpaid', 'Partially Paid')
          AND Invoice_Date < DATE_SUB(CURDATE(), INTERVAL 30 DAY)
    );
END$$


-- ============================================
-- PART 3: APPLICATION ACTION PROCEDURES
-- ============================================

-- *** MODIFIED PROCEDURE (The "Happy Path") ***
-- This procedure now CHECKS and SUBTRACTS stock.
CREATE PROCEDURE sp_AllocateStockForOrder(IN p_DistID INT)
BEGIN
    DECLARE v_Finished INT DEFAULT 0;
    DECLARE v_InvID INT;
    DECLARE v_Qty INT;
    DECLARE v_BatchID INT;
    DECLARE v_CustID INT;

    -- Cursor to loop through all line items for the given order
    DECLARE cur CURSOR FOR 
        SELECT Inventory_ID, Qty_Ordered 
        FROM DistributionOrderLine 
        WHERE Dist_ID = p_DistID;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_Finished = 1;

    -- First, check stock again (race condition)
    IF fn_CheckOrderStockStatus(p_DistID) = '✅ Ready to Fulfill' THEN
        
        -- If stock is OK, loop through the order lines and SUBTRACT stock
        OPEN cur;
        subtract_loop: LOOP
            FETCH cur INTO v_InvID, v_Qty;
            IF v_Finished THEN
                LEAVE subtract_loop;
            END IF;

            -- Find the Batch_ID from the Inventory
            SELECT Batch_ID INTO v_BatchID
            FROM Inventory
            WHERE Inventory_ID = v_InvID;

            -- Subtract from Inventory
            UPDATE Inventory
            SET Quantity = Quantity - v_Qty
            WHERE Inventory_ID = v_InvID;

            -- Subtract from Batch
            UPDATE Batch
            SET AvailableQty = AvailableQty - v_Qty
            WHERE Batch_ID = v_BatchID;

        END LOOP;
        CLOSE cur;

        -- Now, continue with the original logic
        SELECT Cust_ID INTO v_CustID FROM DistributionOrder WHERE Dist_ID = p_DistID;
        
        -- 1. Update Order Status
        UPDATE DistributionOrder
        SET Status = 'Allocated - Ready to Ship'
        WHERE Dist_ID = p_DistID;
        
        -- 2. Create a Shipment record
        INSERT INTO Shipment (Cust_ID, Carrier, Transport_Mode, Dispatch_Date, Shipment_Status)
        VALUES (v_CustID, 'FedEx', 'Truck', CURDATE(), 'Pending Dispatch');
        
        -- 3. Link the shipment
        INSERT INTO ShipmentDetails (Shipment_ID, Dist_ID)
        VALUES (LAST_INSERT_ID(), p_DistID);
        
    ELSE
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: Stock no longer available. Cannot allocate.';
    END IF;
END$$

-- *** NEW PROCEDURE (Deallocate) ***
-- This procedure returns stock and resets the order.
CREATE PROCEDURE sp_DeallocateStockForOrder(IN p_DistID INT)
BEGIN
    -- --- ALL DECLARES MUST COME FIRST ---
    DECLARE v_Finished INT DEFAULT 0;
    DECLARE v_InvID INT;
    DECLARE v_Qty INT;
    DECLARE v_BatchID INT;
    DECLARE v_ShipmentID INT;
    DECLARE v_TotalQty INT;
    DECLARE v_NewAvailableQty INT;
    DECLARE v_CurrentStatus VARCHAR(50);
    
    -- Cursor to loop through all line items for the given order
    DECLARE cur CURSOR FOR 
        SELECT Inventory_ID, Qty_Ordered 
        FROM DistributionOrderLine 
        WHERE Dist_ID = p_DistID;
        
    -- Handler must come AFTER the cursor it handles
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_Finished = 1;
    -- --- END OF DECLARES ---

    -- Now, the logic can begin
    SELECT Status INTO v_CurrentStatus FROM DistributionOrder WHERE Dist_ID = p_DistID;
    
    IF v_CurrentStatus = 'Allocated - Ready to Ship' THEN

        -- Loop through the order lines and ADD stock back
        OPEN cur;
        add_loop: LOOP
            FETCH cur INTO v_InvID, v_Qty;
            IF v_Finished THEN
                LEAVE add_loop;
            END IF;

            -- Find the Batch_ID from the Inventory
            SELECT Batch_ID INTO v_BatchID
            FROM Inventory
            WHERE Inventory_ID = v_InvID;

            -- Add to Inventory
            UPDATE Inventory
            SET Quantity = Quantity + v_Qty
            WHERE Inventory_ID = v_InvID;

            -- Add to Batch (with the "cap" logic to prevent errors)
            SELECT TotalQty INTO v_TotalQty FROM Batch WHERE Batch_ID = v_BatchID;
            SELECT AvailableQty INTO v_NewAvailableQty FROM Batch WHERE Batch_ID = v_BatchID;
            SET v_NewAvailableQty = v_NewAvailableQty + v_Qty;
            
            IF v_NewAvailableQty > v_TotalQty THEN
                SET v_NewAvailableQty = v_TotalQty;
            END IF;

            UPDATE Batch SET AvailableQty = v_NewAvailableQty WHERE Batch_ID = v_BatchID;

        END LOOP;
        CLOSE cur;
        
        -- Find and delete the associated Shipment
        SELECT Shipment_ID INTO v_ShipmentID FROM ShipmentDetails WHERE Dist_ID = p_DistID LIMIT 1;
        IF v_ShipmentID IS NOT NULL THEN
            DELETE FROM ShipmentDetails WHERE Shipment_ID = v_ShipmentID;
            DELETE FROM Shipment WHERE Shipment_ID = v_ShipmentID;
        END IF;
        
        -- Set the order status back to "Processing"
        UPDATE DistributionOrder
        SET Status = 'Processing'
        WHERE Dist_ID = p_DistID;
        
    ELSE
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: Order is not in an "Allocated" state.';
    END IF;
END$$

-- *** MODIFIED PROCEDURE (Cancel) ***
-- This procedure is now simpler. It only deletes records for
-- "Processing" orders where stock was never taken.
CREATE PROCEDURE sp_CancelDistributionOrder(
    IN p_DistID INT
)
BEGIN
    DECLARE v_CurrentStatus VARCHAR(50);
    SELECT Status INTO v_CurrentStatus FROM DistributionOrder WHERE Dist_ID = p_DistID;

    -- Only allow canceling of orders that have not been allocated
    IF v_CurrentStatus = 'Processing' THEN
        DELETE FROM DistributionOrderLine
        WHERE Dist_ID = p_DistID;
        
        DELETE FROM DistributionOrder
        WHERE Dist_ID = p_DistID;
    ELSE
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: Cannot cancel an allocated order. Please deallocate first.';
    END IF;
END$$


-- *** NEW PROCEDURE (The "Problem Path") ***
-- This procedure generates a new PO for a "Blocked" order.
-- THIS IS THE CORRECTED 5-ARGUMENT VERSION
-- Create the procedure with the CORRECT status update
CREATE PROCEDURE sp_GeneratePurchaseOrdersForShortfall(
    IN p_DistID INT,
    IN p_SupplierID INT,
    IN p_RawMaterialID INT,
    IN p_RequiredQty DECIMAL(10,2),
    IN p_UnitPrice DECIMAL(10,2)
)
BEGIN
    DECLARE v_NewPO_ID INT;
    
    -- 1. Create the Purchase Order
    INSERT INTO PurchaseOrder (Supplier_ID, OrderDate, ExpectedDelivery, Status)
    VALUES (p_SupplierID, CURDATE(), DATE_ADD(CURDATE(), INTERVAL 7 DAY), 'Pending');
    
    SET v_NewPO_ID = LAST_INSERT_ID();
    
    -- 2. Create the Purchase Order Line Item
    INSERT INTO POLineItem (PO_ID, Product_ID, Quantity, UnitPrice)
    VALUES (v_NewPO_ID, p_RawMaterialID, p_RequiredQty, p_UnitPrice);
    
    -- 3. Update the original Distribution Order status
    -- *** THIS IS THE FIX: ***
    UPDATE DistributionOrder
    SET Status = 'Pending PO' -- Was 'Pending Raw Materials'
    WHERE Dist_ID = p_DistID;
    
    -- 4. Send back the new PO ID to the application
    SELECT v_NewPO_ID AS New_PO_ID;
END$$

-- (Other procedures like CreateNewPurchaseOrder, UpdateShipmentStatus remain)
CREATE PROCEDURE sp_CreateNewPurchaseOrder(
    IN p_SupplierID INT,
    IN p_ProductID INT,
    IN p_Quantity INT,
    IN p_UnitPrice DECIMAL(10,2)
)
BEGIN
    DECLARE v_NewPO_ID INT;
    INSERT INTO PurchaseOrder (Supplier_ID, OrderDate, ExpectedDelivery, Status)
    VALUES (p_SupplierID, CURDATE(), DATE_ADD(CURDATE(), INTERVAL 7 DAY), 'Pending');
    SET v_NewPO_ID = LAST_INSERT_ID();
    INSERT INTO POLineItem (PO_ID, Product_ID, Quantity, UnitPrice)
    VALUES (v_NewPO_ID, p_ProductID, p_Quantity, p_UnitPrice);
    SELECT v_NewPO_ID AS New_PO_ID;
END$$

CREATE PROCEDURE sp_UpdateShipmentStatus(
    IN p_ShipmentID INT,
    IN p_NewStatus VARCHAR(50)
)
BEGIN
    UPDATE Shipment
    SET Shipment_Status = p_NewStatus
    WHERE Shipment_ID = p_ShipmentID;
END$$


CREATE PROCEDURE sp_GetAllRawMaterials()
BEGIN
    -- This procedure gets all raw materials for the
    -- procurement form dropdown.
    SELECT 
        p.Product_ID,
        p.Name
    FROM Product p
    JOIN RawMaterial rm ON p.Product_ID = rm.Product_ID
    ORDER BY p.Name;
END$$


CREATE PROCEDURE sp_GetOrderDetailsForTriage(IN p_DistID INT)
BEGIN
    SELECT 
        p.Name AS ProductName,
        dol.Qty_Ordered,
        i.Quantity AS Qty_In_Stock,
        (i.Quantity - dol.Qty_Ordered) AS Shortfall,
        dol.Inventory_ID,
        p.Product_ID
    FROM DistributionOrderLine dol
    JOIN Inventory i ON dol.Inventory_ID = i.Inventory_ID
    JOIN Batch b ON i.Batch_ID = b.Batch_ID
    JOIN Product p ON b.Product_ID = p.Product_ID
    WHERE dol.Dist_ID = p_DistID;
END$$


CREATE PROCEDURE sp_GetRawMaterialNeeds(IN p_FinishedGoodID INT, IN p_QtyNeeded INT)
BEGIN
    SELECT
        p.Name AS RawMaterialName,
        p.Product_ID AS RawMaterialID,
        (boi.QuantityRequired * p_QtyNeeded) AS Qty_Required,
        COALESCE(i.Quantity, 0) AS Qty_In_Stock,
        (COALESCE(i.Quantity, 0) - (boi.QuantityRequired * p_QtyNeeded)) AS Shortfall
    FROM BillOfItems boi
    JOIN Product p ON boi.RawMaterial_ID = p.Product_ID
    LEFT JOIN (
        -- Subquery to get the total stock of each raw material
        SELECT b.Product_ID, SUM(i.Quantity) AS Quantity
        FROM Inventory i
        JOIN Batch b ON i.Batch_ID = b.Batch_ID
        GROUP BY b.Product_ID
    ) i ON boi.RawMaterial_ID = i.Product_ID
    WHERE boi.FinishedGood_ID = p_FinishedGoodID;
END$$


CREATE PROCEDURE sp_GetSuppliersForRawMaterial(IN p_RawMaterialID INT)
BEGIN
    SELECT
        s.Supplier_ID,
        s.Name AS SupplierName,
        sup.ContractPrice,
        sup.MOQ
    FROM Supplies sup
    JOIN Supplier s ON sup.Supplier_ID = s.Supplier_ID
    WHERE sup.Product_ID = p_RawMaterialID;
END$$

CREATE PROCEDURE sp_GetAllPurchaseOrders()
BEGIN
    SELECT 
        po.PO_ID,
        po.OrderDate,
        s.Name AS SupplierName,
        p.Name AS ProductName,
        pli.Quantity,
        pli.UnitPrice,
        po.Status
    FROM PurchaseOrder po
    JOIN Supplier s ON po.Supplier_ID = s.Supplier_ID
    JOIN POLineItem pli ON po.PO_ID = pli.PO_ID
    JOIN Product p ON pli.Product_ID = p.Product_ID
    ORDER BY po.OrderDate DESC, po.PO_ID DESC;
END$$

CREATE PROCEDURE sp_GetUnpaidInvoices()
BEGIN
    SELECT 
        i.Invoice_ID,
        i.Dist_ID,
        c.Cust_Name,
        i.Invoice_Date,
        i.Final_Amount,
        i.Status,
        -- Calculate the outstanding balance
        (i.Final_Amount - COALESCE(p.TotalPaid, 0)) AS Remaining_Balance
    FROM Invoice i
    JOIN DistributionOrder do ON i.Dist_ID = do.Dist_ID
    JOIN Customer c ON do.Cust_ID = c.Cust_ID
    -- Use a subquery to get the sum of payments already made
    LEFT JOIN (
        SELECT Invoice_ID, SUM(Amount_Paid) AS TotalPaid
        FROM Payment
        WHERE Status = 'Completed'
        GROUP BY Invoice_ID
    ) p ON i.Invoice_ID = p.Invoice_ID
    -- Only get invoices that are not fully paid or canceled
    WHERE i.Status IN ('Unpaid', 'Partially Paid')
    ORDER BY i.Invoice_Date;
END$$

CREATE PROCEDURE sp_RecordPayment(
    IN p_InvoiceID INT,
    IN p_AmountPaid DECIMAL(12,2),
    IN p_PayMethod VARCHAR(50)
)
BEGIN
    -- Find the Customer ID from the invoice
    DECLARE v_CustID INT;
    SELECT do.Cust_ID INTO v_CustID
    FROM Invoice i
    JOIN DistributionOrder do ON i.Dist_ID = do.Dist_ID
    WHERE i.Invoice_ID = p_InvoiceID;

    -- Insert the new payment.
    -- This will fire 'trg_payment_after_insert'
    INSERT INTO Payment (Invoice_ID, Cust_ID, Pay_Date, Pay_Method, Amount_Paid, Status, Trans_Ref)
    VALUES (p_InvoiceID, v_CustID, CURDATE(), p_PayMethod, p_AmountPaid, 'Completed', 'ADMIN_ENTRY');
END$$

CREATE PROCEDURE sp_GetAllPayments()
BEGIN
    SELECT 
        p.Pay_ID,
        p.Invoice_ID,
        p.Pay_Date,
        c.Cust_Name,
        p.Amount_Paid,
        p.Pay_Method,
        p.Status
    FROM Payment p
    JOIN Customer c ON p.Cust_ID = c.Cust_ID
    ORDER BY p.Pay_Date DESC, p.Pay_ID DESC;
END$$

DELIMITER ;