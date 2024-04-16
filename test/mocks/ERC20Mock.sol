// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Mock is ERC20 {
    uint8 private decimals_;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) ERC20(_name, _symbol) {
        decimals_ = _decimals;
    }

    function decimals() public view override returns (uint8) {
        return decimals_;
    }

    function mint(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }

    function adminApprove(address owner, address spender, uint256 amount) external {
        _approve(owner, spender, amount);
    }

    function adminTransfer(address sender, address recipient, uint256 amount) external {
        _transfer(sender, recipient, amount);
    }
}
