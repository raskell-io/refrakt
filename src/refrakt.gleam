/// Refrakt — A convention-first web framework for Gleam.
///
/// This module re-exports the core helpers used by generated projects:
/// validation, flash messages, and test utilities.
///
import refrakt/flash
import refrakt/validate

// Re-export flash helpers
pub const set_flash = flash.set_flash

pub const get_flash = flash.get_flash

// Re-export validation helpers
pub const required = validate.required

pub const min_length = validate.min_length

pub const max_length = validate.max_length
