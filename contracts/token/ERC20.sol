// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/ERC20.sol)

pragma solidity ^0.8.20;
import "../interface/IERC20.sol";
import "../interface/draft-IERC6093.sol";
import "../utils/Ownable.sol";

contract ERC20 is IERC20,Ownable,IERC20Errors {

    // Token名称
    string public _name;
    // Token代号
    string public _symbol;
    // totalSupply
    uint256 _totalSupply;
    // decemals
    uint256 public decemals;
    // balance
    mapping(address account => uint256) private _balances;
    // _allowances
    mapping(address account => mapping(address spender => uint256)) private _allowances;

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */
    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }


    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256){
        return _totalSupply;
    }

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address _account) public view returns (uint256){
        return _balances[_account];
    }

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address _owner, address _spender) external view returns (uint256){
        return _allowances[_owner][_spender];
    }

    /**
    * Sets a `value` amount of tokens as the allowance of `spender` over the caller's tokens.
    * Returns a boolean value indicating whether the operation succeeded.
    */
    function approve(address _spender, uint256 _value) external returns (bool){
        address owner = _msgSender();
        if(_spender == address(0)){
            revert ERC20InvalidSpender(address(0));
        }
        _allowances[owner][_spender] += _value;
        emit Approval(owner,_spender,_value);
        return true;
    }


    function mint(address to, uint256 value) public {
        require(to != address(0),"Invalid Address");
        _update(address(0),to,value);
    }

    function burn(address from, uint256 value) external{
        require(from != address(0),"Invalid Address");
        _update(from,address(0),value);
    }

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool){
        address owner = _msgSender();
        require(_balances[owner] >= value, "Insufficient balance");
        _transfer(owner, to, value);
        return true;
    }

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool){
        address owner = _msgSender();
        require(_balances[from] >= value, "Insufficient balance");
        _spendAllowance(from,owner,value);
        _transfer(from,to,value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) private {
        if(from==address(0)){
            revert ERC20InvalidSender(address(0));
        }
        if(to==address(0)){
            revert ERC20InvalidReceiver(address(0));
        }
        _update(from,to,value);
    }

    /**
     * @dev Transfers a `value` amount of tokens from `from` to `to`, or alternatively mints (or burns) if `from`
     * (or `to`) is the zero address. All customizations to transfers, mints, and burns should be done by overriding
     * this function.
     *
     * Emits a {Transfer} event.
     */
    function _update(address from, address to, uint256 value) internal virtual {
        if (from == address(0)) {
            // Overflow check required: The rest of the code assumes that totalSupply never overflows
            _totalSupply += value;
        } else {
            uint256 fromBalance = _balances[from];
            if (fromBalance < value) {
                revert ERC20InsufficientBalance(from, fromBalance, value);
            }
            unchecked {
                // Overflow not possible: value <= fromBalance <= totalSupply.
                _balances[from] = fromBalance - value;
            }
        }

        if (to == address(0)) {
            unchecked {
                // Overflow not possible: value <= totalSupply or value <= fromBalance <= totalSupply.
                _totalSupply -= value;
            }
        } else {
            unchecked {
                // Overflow not possible: balance + value is at most totalSupply, which we know fits into a uint256.
                _balances[to] += value;
            }
        }

        emit Transfer(from, to, value);
    }


    /**
     * @dev Updates `owner` s allowance for `spender` based on spent `value`.
     *
     * Does not update the allowance value in case of infinite allowance.
     * Revert if not enough allowance is available.
     *
     * Does not emit an {Approval} event.
     */
    function _spendAllowance(address owner, address spender, uint256 value) internal virtual {
        uint256 currentAllowance = _allowances[owner][spender];
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < value) {
                revert ERC20InsufficientAllowance(spender, currentAllowance, value);
            }
            unchecked {
                if(spender == address(0)){
                    revert ERC20InvalidSpender(address(0));
                }
                _allowances[owner][spender] = value - currentAllowance;
            }
        }
    }

}