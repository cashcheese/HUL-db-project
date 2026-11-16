-- ===================================================
-- HUL DB - FINAL TRIGGERS SCRIPT (v2.1 - Optimistic)
--
-- NOTE: Sales-related stock triggers have been REMOVED.
-- Stock logic is now handled in stored procedures.
-- ===================================================

USE hul_db;

-- ============================================
-- PART 0: DROP ALL EXISTING OBJECTS FIRST
-- ============================================

-- Drop the Helper Procedure
DROP PROCEDURE IF EXISTS sp_update_invoice_status;

-- Drop all Triggers
DROP TRIGGER IF EXISTS trg_Before_MO_Input_CheckStock;
DROP TRIGGER IF EXISTS trg_After_MO_Input_ConsumeStock;
DROP TRIGGER IF EXISTS trg_After_MO_Input_Delete_ReturnStock;
DROP TRIGGER IF EXISTS trg_After_MO_Output_CreateInventory;
DROP TRIGGER IF EXISTS trg_After_MO_Output_Delete_RemoveInventory;
DROP TRIGGER IF EXISTS trg_Before_DOLine_Insert_CheckStock;
DROP TRIGGER IF EXISTS trg_After_DOLine_Insert_UpdateStock;
DROP TRIGGER IF EXISTS trg_After_DOLine_Delete_ReturnStock;
DROP TRIGGER IF EXISTS trg_Before_Batch_Insert_SetExpiry;
DROP TRIGGER IF EXISTS trg_shipment_status_update;
DROP TRIGGER IF EXISTS trg_invoice_insert_checks;
DROP TRIGGER IF EXISTS trg_payment_over_payment_insert;
DROP TRIGGER IF EXISTS trg_payment_before_update;
DROP TRIGGER IF EXISTS trg_payment_after_insert;
DROP TRIGGER IF EXISTS trg_payment_after_update;
DROP TRIGGER IF EXISTS trg_payment_after_delete;
DROP TRIGGER IF EXISTS trg_channel_prevent_delete;
DROP TRIGGER IF EXISTS trg_customer_standardize_insert;
DROP TRIGGER IF EXISTS trg_customer_standardize_update;

-- ============================================
-- PART 1: ADD STORED PROCEDURE (For Payment Triggers)
-- ============================================

DELIMITER $$
CREATE PROCEDURE sp_update_invoice_status(IN p_InvoiceID INT)
BEGIN
    DECLARE v_TotalPaid DECIMAL(12,2);
    DECLARE v_FinalAmount DECIMAL(12,2);
    DECLARE v_NewStatus VARCHAR(50);

    -- Get the final amount of the invoice
    SELECT Final_Amount
    INTO v_FinalAmount
    FROM Invoice
    WHERE Invoice_ID = p_InvoiceID;

    -- Recalculate the total of *only completed* payments
    SELECT COALESCE(SUM(Amount_Paid), 0)
    INTO v_TotalPaid
    FROM Payment
    WHERE Invoice_ID = p_InvoiceID
      AND Status = 'Completed';
      
    -- Determine the new status
    IF v_TotalPaid >= v_FinalAmount THEN
        SET v_NewStatus = 'Paid';
    ELSEIF v_TotalPaid > 0 THEN
        SET v_NewStatus = 'Partially Paid';
    ELSE
        SET v_NewStatus = 'Unpaid';
    END IF;
    
    -- Update the Invoice table
    UPDATE Invoice
    SET Status = v_NewStatus
    WHERE Invoice_ID = p_InvoiceID;
END$$
DELIMITER ;

-- ============================================
-- PART 2: ADD ALL TRIGGERS
-- ============================================

-- --------------------------------------------
-- Module: Manufacturing (Stock Consumption)
-- --------------------------------------------
DELIMITER $$
CREATE TRIGGER trg_Before_MO_Input_CheckStock
BEFORE INSERT ON ManufacturingOrderInput
FOR EACH ROW
BEGIN
    DECLARE v_AvailableStock INT;
    SELECT AvailableQty INTO v_AvailableStock
    FROM Batch
    WHERE Batch_ID = NEW.Batch_ID;

    IF v_AvailableStock < NEW.Qty_Consumed THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: Insufficient raw material. Cannot start manufacturing order.';
    END IF;
END$$
DELIMITER ;

DELIMITER $$
CREATE TRIGGER trg_After_MO_Input_ConsumeStock
AFTER INSERT ON ManufacturingOrderInput
FOR EACH ROW
BEGIN
    UPDATE Batch
    SET AvailableQty = AvailableQty - NEW.Qty_Consumed
    WHERE Batch_ID = NEW.Batch_ID;

    UPDATE Inventory
    SET Quantity = Quantity - NEW.Qty_Consumed
    WHERE Batch_ID = NEW.Batch_ID;
END$$
DELIMITER ;

-- Handles the reversal of a manufacturing consumption
DELIMITER $$
CREATE TRIGGER trg_After_MO_Input_Delete_ReturnStock
AFTER DELETE ON ManufacturingOrderInput
FOR EACH ROW
BEGIN
    -- Add the consumed quantity back to the raw material Batch
    UPDATE Batch
    SET AvailableQty = AvailableQty + OLD.Qty_Consumed
    WHERE Batch_ID = OLD.Batch_ID;

    -- Add the consumed quantity back to the Inventory
    UPDATE Inventory
    SET Quantity = Quantity + OLD.Qty_Consumed
    WHERE Batch_ID = OLD.Batch_ID;
END$$
DELIMITER ;

-- --------------------------------------------
-- Module: Manufacturing (Stock Creation)
-- --------------------------------------------
DELIMITER $$
CREATE TRIGGER trg_After_MO_Output_CreateInventory
AFTER INSERT ON ManufacturingOrderOutput
FOR EACH ROW
BEGIN
    DECLARE factory_warehouse_id INT;
    -- Find the primary warehouse (simplification)
    SELECT Warehouse_ID INTO factory_warehouse_id FROM Warehouse LIMIT 1;

    INSERT INTO Inventory (Batch_ID, Warehouse_ID, Quantity, LastUpdated)
    VALUES (NEW.Batch_ID, factory_warehouse_id, NEW.Qty_Produced, CURDATE());
END$$
DELIMITER ;

-- Handles the reversal of a production output (deletes phantom inventory)
DELIMITER $$
CREATE TRIGGER trg_After_MO_Output_Delete_RemoveInventory
AFTER DELETE ON ManufacturingOrderOutput
FOR EACH ROW
BEGIN
    -- Deletes the corresponding Inventory record if a production output is deleted.
    DELETE FROM Inventory
    WHERE Batch_ID = OLD.Batch_ID;
END$$
DELIMITER ;

-- --------------------------------------------
-- Module: Sales (Stock Allocation)
-- --------------------------------------------

-- *** ALL SALES TRIGGERS (CheckStock, UpdateStock, ReturnStock)
-- *** ARE REMOVED in v2.1.
-- *** This logic is now handled by the stored procedures
-- *** sp_AllocateStockForOrder and sp_DeallocateStockForOrder.

-- --------------------------------------------
-- Module: Batch (Data Automation)
-- --------------------------------------------
-- Automatically calculates ExpiryDate when a new batch is created.
DELIMITER $$
CREATE TRIGGER trg_Before_Batch_Insert_SetExpiry
BEFORE INSERT ON Batch
FOR EACH ROW
BEGIN
    DECLARE v_ShelfLife INT;

    -- Check if ExpiryDate is already set (don't override)
    IF NEW.ExpiryDate IS NULL THEN
        -- Find the shelf life from either FinishedGood or RawMaterial
        SELECT ShelfLife INTO v_ShelfLife
        FROM FinishedGood
        WHERE Product_ID = NEW.Product_ID;

        IF v_ShelfLife IS NULL THEN
            SELECT ShelfLife INTO v_ShelfLife
            FROM RawMaterial
            WHERE Product_ID = NEW.Product_ID;
        END IF;

        -- If we found a shelf life, calculate and set the ExpiryDate
        IF v_ShelfLife IS NOT NULL THEN
            SET NEW.ExpiryDate = DATE_ADD(NEW.Mfg_Date, INTERVAL v_ShelfLife DAY);
        END IF;
    END IF;
END$$
DELIMITER ;

-- --------------------------------------------
-- Module: Shipment (Downstream Status Update)
-- --------------------------------------------
DELIMITER $$
CREATE TRIGGER trg_shipment_status_update
AFTER UPDATE ON Shipment
FOR EACH ROW
BEGIN
    IF NEW.Shipment_Status = 'Delivered' AND OLD.Shipment_Status != 'Delivered' THEN
        UPDATE DistributionOrder
        SET Status = 'Delivered'
        WHERE Dist_ID IN (
            SELECT Dist_ID FROM ShipmentDetails
            WHERE Shipment_ID = NEW.Shipment_ID
        );
    END IF;
END$$
DELIMITER ;

-- --------------------------------------------
-- Module: Invoice (Auto-Calculation & Protection)
-- --------------------------------------------
DELIMITER $$
CREATE TRIGGER trg_invoice_insert_checks
BEFORE INSERT ON Invoice
FOR EACH ROW
BEGIN
    DECLARE v_OrderTotal DECIMAL(12,2);
    DECLARE v_AlreadyInvoiced DECIMAL(12,2);
    
    -- === 1. Auto-Calculation ===
    IF NEW.Discount IS NULL THEN
        SET NEW.Discount = 0;
    END IF;
    
    SET NEW.Final_Amount = (NEW.Amount + NEW.Tax) - NEW.Discount;

    -- === 2. Over-Invoicing Protection ===
    SELECT SUM(Qty_Dispatched * Price_Per_Unit)
    INTO v_OrderTotal
    FROM DistributionOrderLine
    WHERE Dist_ID = NEW.Dist_ID;
    
    SELECT COALESCE(SUM(Final_Amount), 0)
    INTO v_AlreadyInvoiced
    FROM Invoice
    WHERE Dist_ID = NEW.Dist_ID;
    
    IF (v_AlreadyInvoiced + NEW.Final_Amount) > v_OrderTotal THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Over-Invoicing Error: The new total would exceed the order total.';
    END IF;
END$$
DELIMITER ;

-- --------------------------------------------
-- Module: Payment (Protection & Status Updates)
-- --------------------------------------------
DELIMITER $$
CREATE TRIGGER trg_payment_over_payment_insert
BEFORE INSERT ON Payment
FOR EACH ROW
BEGIN
    DECLARE v_InvoiceTotal DECIMAL(12,2);
    DECLARE v_AlreadyPaid DECIMAL(12,2);

    IF NEW.Status = 'Completed' THEN
        SELECT Final_Amount
        INTO v_InvoiceTotal
        FROM Invoice
        WHERE Invoice_ID = NEW.Invoice_ID;
        
        SELECT COALESCE(SUM(Amount_Paid), 0)
        INTO v_AlreadyPaid
        FROM Payment
        WHERE Invoice_ID = NEW.Invoice_ID
          AND Status = 'Completed';

        IF (v_AlreadyPaid + NEW.Amount_Paid) > v_InvoiceTotal THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Over-Payment Error: The new total would exceed the invoice total.';
        END IF;
    END IF;
END$$
DELIMITER ;

DELIMITER $$
CREATE TRIGGER trg_payment_before_update
BEFORE UPDATE ON Payment
FOR EACH ROW
BEGIN
    DECLARE v_InvoiceTotal DECIMAL(12,2);
    DECLARE v_AlreadyPaid DECIMAL(12,2);

    -- Rule 1: Prevent moving payment
    IF OLD.Invoice_ID != NEW.Invoice_ID THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_text = 'Error: A payment cannot be moved from one invoice to another.';
    END IF;

    -- Rule 2: Prevent over-payment on update
    IF NEW.Status = 'Completed' THEN
        SELECT Final_Amount
        INTO v_InvoiceTotal
        FROM Invoice
        WHERE Invoice_ID = NEW.Invoice_ID;
        
        -- Get sum of all *other* completed payments
        SELECT COALESCE(SUM(Amount_Paid), 0)
        INTO v_AlreadyPaid
        FROM Payment
        WHERE Invoice_ID = NEW.Invoice_ID
          AND Status = 'Completed'
          AND Pay_ID != NEW.Pay_ID;

        IF (v_AlreadyPaid + NEW.Amount_Paid) > v_InvoiceTotal THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Over-Payment Error: The new total would exceed the invoice total.';
        END IF;
    END IF;
END$$
DELIMITER ;

DELIMITER $$
CREATE TRIGGER trg_payment_after_insert
AFTER INSERT ON Payment
FOR EACH ROW
BEGIN
    CALL sp_update_invoice_status(NEW.Invoice_ID);
END$$
DELIMITER ;

DELIMITER $$
CREATE TRIGGER trg_payment_after_update
AFTER UPDATE ON Payment
FOR EACH ROW
BEGIN
    CALL sp_update_invoice_status(NEW.Invoice_ID);
END$$
DELIMITER ;

DELIMITER $$
CREATE TRIGGER trg_payment_after_delete
AFTER DELETE ON Payment
FOR EACH ROW
BEGIN
    CALL sp_update_invoice_status(OLD.Invoice_ID);
END$$
DELIMITER ;

-- --------------------------------------------
-- Module: Master Data (Integrity & Standardization)
-- --------------------------------------------
DELIMITER $$
CREATE TRIGGER trg_channel_prevent_delete
BEFORE DELETE ON Channel
FOR EACH ROW
BEGIN
    DECLARE v_Count INT;
    SELECT COUNT(*)
    INTO v_Count
    FROM Customer_Channel
    WHERE Channel_ID = OLD.Channel_ID;
    
    IF v_Count > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cannot delete channel: It is still assigned to one or more customers.';
    END IF;
END$$
DELIMITER ;

DELIMITER $$
CREATE TRIGGER trg_customer_standardize_insert
BEFORE INSERT ON Customer
FOR EACH ROW
BEGIN
    SET NEW.Cust_Name = UPPER(NEW.Cust_Name);
END$$
DELIMITER ;

DELIMITER $$
CREATE TRIGGER trg_customer_standardize_update
BEFORE UPDATE ON Customer
FOR EACH ROW
BEGIN
    SET NEW.Cust_Name = UPPER(NEW.Cust_Name);
END$$
DELIMITER ;