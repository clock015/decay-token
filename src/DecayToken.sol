// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import {UD60x18, ud, convert} from "prb-math/UD60x18.sol";

contract DecayToken is Context, IERC20, IERC20Metadata {
    string private _name;
    string private _symbol;
    uint256 public immutable halfLife;

    struct AccountState {
        uint256 lastBalance;
        uint32 lastUpdateTime;
    }

    mapping(address => AccountState) private _states;
    mapping(address => mapping(address => uint256)) private _allowances;

    AccountState private _totalState;

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply,
        uint256 halfLifeSeconds
    ) {
        _name = name_;
        _symbol = symbol_;
        halfLife = halfLifeSeconds;

        uint256 amount = initialSupply * 10 ** decimals();

        _totalState = AccountState(amount, uint32(block.timestamp));
        _states[_msgSender()] = AccountState(amount, uint32(block.timestamp));

        emit Transfer(address(0), _msgSender(), amount);
    }

    function name() public view override returns (string memory) {
        return _name;
    }
    function symbol() public view override returns (string memory) {
        return _symbol;
    }
    function decimals() public pure override returns (uint8) {
        return 18;
    }

    /**
     * @dev 修复后的计算逻辑
     */
    function _getDecayedValue(
        uint256 lastValue,
        uint256 lastTime
    ) internal view returns (uint256) {
        if (lastValue == 0 || lastTime >= block.timestamp) return lastValue;

        uint256 elapsed = block.timestamp - lastTime;

        // n = elapsed / halfLife (这里使用 convert 是正确的，因为 elapsed 是纯秒数整数)
        UD60x18 n = convert(elapsed).div(convert(halfLife));

        // 安全阈值
        if (n.unwrap() > 130e18) return 0;

        UD60x18 factor = n.exp2();

        // 【核心修复点】：使用 ud(lastValue) 而不是 convert(lastValue)
        // 因为 lastValue 已经是 1e18 精度了。
        // 计算: current = lastValue / 2^n
        return ud(lastValue).div(factor).unwrap();
    }

    function _settle(address account) internal returns (uint256) {
        uint256 current = _getDecayedValue(
            _states[account].lastBalance,
            _states[account].lastUpdateTime
        );
        _states[account].lastBalance = current;
        _states[account].lastUpdateTime = uint32(block.timestamp);
        return current;
    }

    function _settleTotalSupply() internal returns (uint256) {
        uint256 current = _getDecayedValue(
            _totalState.lastBalance,
            _totalState.lastUpdateTime
        );
        _totalState.lastBalance = current;
        _totalState.lastUpdateTime = uint32(block.timestamp);
        return current;
    }

    function totalSupply() public view override returns (uint256) {
        return
            _getDecayedValue(
                _totalState.lastBalance,
                _totalState.lastUpdateTime
            );
    }

    function balanceOf(address account) public view override returns (uint256) {
        return
            _getDecayedValue(
                _states[account].lastBalance,
                _states[account].lastUpdateTime
            );
    }

    function transfer(
        address to,
        uint256 amount
    ) public override returns (bool) {
        _executeTransfer(_msgSender(), to, amount);
        return true;
    }

    function allowance(
        address owner,
        address spender
    ) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(
        address spender,
        uint256 amount
    ) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        _spendAllowance(from, _msgSender(), amount);
        _executeTransfer(from, to, amount);
        return true;
    }

    function _executeTransfer(
        address from,
        address to,
        uint256 amount
    ) internal {
        require(from != address(0), "Transfer from zero");
        require(to != address(0), "Transfer to zero");

        _settleTotalSupply();
        uint256 fromBalance = _settle(from);
        uint256 toBalance = _settle(to);

        require(fromBalance >= amount, "Exceeds decayed balance");

        unchecked {
            _states[from].lastBalance = fromBalance - amount;
            _states[to].lastBalance = toBalance + amount;
        }

        emit Transfer(from, to, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal {
        uint256 currentAllowance = _allowances[owner][spender];
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "Insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    function mint(address account, uint256 amount) external {
        _settleTotalSupply();
        uint256 accountBalance = _settle(account);
        _totalState.lastBalance += amount;
        _states[account].lastBalance = accountBalance + amount;
        emit Transfer(address(0), account, amount);
    }
}
