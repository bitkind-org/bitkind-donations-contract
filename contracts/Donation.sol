// SPDX-License-Identifier: GNU-3
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Donation is Ownable {
    struct TokenInfo {
        IERC20 token;
        uint256 feePercentage;
    }

    mapping(string => TokenInfo) public tokens;
    uint256 public nativeFeePercentage = 0;

    event DonationMade(
        uint256 indexed storyId,
        address indexed receiver,
        address indexed sender,
        string tokenSymbol,
        uint256 grossAmount,
        uint256 netAmount,
        uint256 serviceFee,
        uint256 serviceTips
    );

    constructor() Ownable(msg.sender) {}

    function addToken(
        string memory symbol,
        address tokenAddress,
        uint256 feePercentage
    ) external onlyOwner {
        require(
            tokenAddress != address(0),
            "Token address cannot be the zero address"
        );
        tokens[symbol] = TokenInfo(IERC20(tokenAddress), feePercentage);
    }

    function deleteToken(string memory symbol) external onlyOwner {
        require(
            tokens[symbol].token != IERC20(address(0)),
            "Token not registered"
        );
        delete tokens[symbol];
    }

    function donate(
        uint256 storyId,
        string memory tokenSymbol,
        address receiver,
        uint256 amount,
        uint256 tips
    ) external payable {
        require(amount > 0, "Donation amount must be positive");
        require(receiver != address(0), "Receiver cannot be the zero address");

        // Donation using the native blockchain currency (ETH/BNB)
        if (keccak256(bytes(tokenSymbol)) == keccak256(bytes("NATIVE"))) {
            uint256 totalTransactionAmount = amount + tips;
            require(
                msg.value == totalTransactionAmount,
                "NATIVE value sent does not match the specified amount"
            );

            uint256 fee = (amount * nativeFeePercentage) / 100;
            uint256 totalDeductions = fee + tips;
            require(
                amount > totalDeductions,
                "Total transaction amount is too low after including tips"
            );

            uint256 amountToReceiver = amount - fee;
            (bool sent, ) = receiver.call{value: amountToReceiver}("");
            require(sent, "Failed to send NATIVE");

            emit DonationMade(
                storyId,
                receiver,
                msg.sender,
                "NATIVE",
                amount,
                amountToReceiver,
                fee,
                tips
            );
        } else {
            // ERC20 token donation
            TokenInfo storage token = tokens[tokenSymbol];
            require(token.token != IERC20(address(0)), "Token not registered");

            uint256 fee = (amount * token.feePercentage) / 100;
            uint256 totalDeductions = fee + tips;
            require(amount > totalDeductions, "Donation amount is too low");

            uint256 amountToReceiver = amount - fee;

            // Trensfer tokens
            require(
                token.token.transferFrom(
                    msg.sender,
                    address(this),
                    totalDeductions
                ),
                "Failed to transfer fees and tips"
            );
            require(
                token.token.transferFrom(
                    msg.sender,
                    receiver,
                    amountToReceiver
                ),
                "Failed to transfer amount to receiver"
            );

            emit DonationMade(
                storyId,
                receiver,
                msg.sender,
                tokenSymbol,
                amount,
                amountToReceiver,
                fee,
                tips
            );
        }
    }

    function setFeeRateForNative(
        uint256 _feePercentage
    ) external onlyOwner {
        nativeFeePercentage = _feePercentage;
    }

    function setFeeRateForToken(
        string memory symbol,
        uint256 newFeePercentage
    ) external onlyOwner {
        require(
            tokens[symbol].token != IERC20(address(0)),
            "Token not registered"
        );
        tokens[symbol].feePercentage = newFeePercentage;
    }

    function withdrawNativeToken(
        address payable to,
        uint256 amount
    ) external onlyOwner {
        require(address(this).balance >= amount, "Insufficient balance");
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "Failed to send Ether");
    }

    function withdrawToken(
        string memory tokenSymbol,
        address to,
        uint256 amount
    ) external onlyOwner {
        TokenInfo storage token = tokens[tokenSymbol];
        require(token.token != IERC20(address(0)), "Token not registered");
        require(
            token.token.balanceOf(address(this)) >= amount,
            "Insufficient token balance"
        );

        require(token.token.transfer(to, amount), "Failed to transfer token");
    }
}