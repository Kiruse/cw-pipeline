#[cfg(not(feature = "library"))]
use cosmwasm_std::entry_point;
use cosmwasm_std::{DepsMut, Env, MessageInfo, Response};

use crate::ContractResult;
use crate::msg::ExecuteMsg;

#[cfg_attr(not(feature = "library"), entry_point)]
pub fn execute(
  _deps: DepsMut,
  _env: Env,
  _info: MessageInfo,
  _msg: ExecuteMsg,
) -> ContractResult<Response> {
  unimplemented!()
}
