USE hul_db;

UPDATE Inventory SET Quantity = 500 WHERE Inventory_ID = 5001;
UPDATE Inventory SET Quantity = 300 WHERE Inventory_ID = 5002;
UPDATE Inventory SET Quantity = 400 WHERE Inventory_ID = 5003;
UPDATE Batch SET AvailableQty = 500 WHERE Batch_ID = 7010;
UPDATE Batch SET AvailableQty = 300 WHERE Batch_ID = 7011;
UPDATE Batch SET AvailableQty = 400 WHERE Batch_ID = 7012;