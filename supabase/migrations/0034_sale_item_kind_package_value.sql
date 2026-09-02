-- Phase 2: adds the PACKAGE value to sale_item_kind.
--
-- This is deliberately its OWN migration, containing nothing else.
-- PostgreSQL does not allow a newly added enum value to be used (compared,
-- cast from a literal, etc.) within the same transaction that added it --
-- and a multi-statement SQL Editor paste runs as a single implicit
-- transaction. 0035_sale_items_package_column.sql (which needs to write
-- `item_type = 'PACKAGE'` into a CHECK constraint) must therefore be
-- applied as a separate paste/transaction, after this one has committed.
alter type sale_item_kind add value 'PACKAGE';