// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

// import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

// library PriceFeed {
//     error PriceFeed__InvalidPriceFeedAddress();
//     error PriceFeed__PriceFeedNotAvailable();

//     uint256 private constant ETH_USD_PRICE_FEED = 0x694AA1769357215DE4FAC081bf1f309aDC325306; // Chainlink ETH/USD price feed address

//     function getLatestPriceETH_USD() internal view returns (int256) {
//         AggregatorV3Interface priceFeed = AggregatorV3Interface(ETH_USD_PRICE_FEED);
//         (, int256 price,,,) = priceFeed.latestRoundData();

//         if (price <= 0) {
//             revert PriceFeed__PriceFeedNotAvailable();
//         }

//         return price;
//     }
// }
