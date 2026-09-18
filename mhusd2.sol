// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin TRON Contracts ^5.6.0
pragma solidity ^0.8.26;

/*
    ================================================================
    MHUSD - Muhammadreza Haghiri USD
    ================================================================

    TOKEN:
        Muhammadreza Haghiri's USD

    SYMBOL:
        MHUSD

    TARGET:
        1 MHUSD = 1 USD

    BLOCKCHAIN:
        TRON

    MECHANISM:
        - Users deposit TRX.
        - The contract automatically reads the TRX/USD price
          from an on-chain oracle.
        - The user receives $1 worth of MHUSD for every $1
          worth of TRX deposited.
        - A 0.05% minting fee is charged.
        - The minting fee remains inside the contract.
        - MHUSD can be redeemed for the corresponding TRX value.
        - Redeemed MHUSD is burned.
        - There is no redemption fee.

    ORACLE:
        WINkLink / Chainlink-compatible AggregatorV3Interface.

        The owner sets the official TRX/USD feed address once
        using `setPriceFeed()`.

        After that, users do NOT manually set the TRX price.

    IMPORTANT:
        Smart contracts cannot directly access the internet.
        An oracle is therefore required to bring TRX/USD data
        onto TRON.

        The contract checks:
            - price > 0
            - price feed exists
            - price is not stale
            - round is complete

        The oracle feed address itself is controlled by the owner.

        For production, use the official current WINkLink or
        Chainlink TRX/USD proxy address for TRON Mainnet.
    ================================================================
*/


import {Ownable} from "@openzeppelin/tron-contracts/access/Ownable.sol";
import {TRC20} from "@openzeppelin/tron-contracts/token/TRC20/TRC20.sol";
import {TRC20Burnable} from "@openzeppelin/tron-contracts/token/TRC20/extensions/TRC20Burnable.sol";
import {TRC20Permit} from "@openzeppelin/tron-contracts/token/TRC20/extensions/TRC20Permit.sol";


/*
    ================================================================
    ORACLE INTERFACE
    ================================================================

    This is the standard Chainlink-compatible price-feed interface
    used by WINkLink.

    The contract does not need to import an external oracle library.

    We only need the functions necessary to retrieve the latest
    TRX/USD price.
*/
interface AggregatorV3Interface {

    /*
        Returns the number of decimals used by the price feed.

        Example:

            8 decimals

            $0.30

        is represented as:

            30,000,000
    */
    function decimals()
        external
        view
        returns (uint8);


    /*
        Returns the latest price round.

        Returns:

            roundId
            answer
            startedAt
            updatedAt
            answeredInRound

        `answer` is the actual TRX/USD price.

        `updatedAt` tells us when the oracle last updated it.
    */
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}


contract MuhammadrezaHaghiriSUSD
    is TRC20,
      TRC20Burnable,
      Ownable,
      TRC20Permit
{

    /*
        ============================================================
        CONSTANTS
        ============================================================
    */


    /*
        10,000 basis points = 100%.

        Therefore:

            5 / 10,000 = 0.05%
    */
    uint256 public constant BASIS_POINTS = 10_000;


    /*
        Minting fee:

            5 basis points = 0.05%
    */
    uint256 public constant MINT_FEE_BPS = 5;


    /*
        Internal price precision.

        All prices returned by the oracle are normalized to
        8 decimal places.
    */
    uint256 public constant PRICE_PRECISION = 1e8;


    /*
        Maximum age accepted for an oracle price.

        If the oracle hasn't updated for more than one hour,
        minting/redemption will stop instead of using an old price.

        This prevents an old TRX price from being used indefinitely.
    */
    uint256 public constant MAX_PRICE_AGE = 24 hours;


    /*
        ============================================================
        STATE VARIABLES
        ============================================================
    */


    /*
        Address of the TRX/USD oracle.

        This should be the official WINkLink or Chainlink-compatible
        TRX/USD proxy address on TRON Mainnet.

        It is initially address(0) until the owner sets it.
    */
    AggregatorV3Interface public priceFeed;


    /*
        Last normalized TRX/USD price read from the oracle.

        This is stored only for transparency.

        It is NOT manually editable.
    */
    uint256 public trxUsdPrice;


    /*
        Timestamp of the last successful oracle read.
    */
    uint256 public priceUpdatedAt;


    /*
        Total TRX currently recorded as user collateral.

        Minting fees are NOT included in this number.
    */
    uint256 public totalBackingTRX;


    /*
        Total accumulated minting fees.

        These fees remain in the contract until the owner
        withdraws them.
    */
    uint256 public accumulatedMintFees;


    /*
        ============================================================
        EVENTS
        ============================================================
    */


    /*
        Emitted whenever the oracle address is changed.
    */
    event PriceFeedUpdated(
        address indexed oldFeed,
        address indexed newFeed
    );


    /*
        Emitted whenever the contract successfully obtains
        a fresh TRX/USD price from the oracle.
    */
    event PriceUpdated(
        uint256 oldPrice,
        uint256 newPrice,
        uint256 timestamp
    );


    /*
        Emitted when MHUSD is minted.
    */
    event MHUSDMinted(
        address indexed user,
        uint256 trxBacking,
        uint256 fee,
        uint256 mhusdMinted
    );


    /*
        Emitted when MHUSD is redeemed.
    */
    event MHUSDRedeemed(
        address indexed user,
        uint256 mhusdBurned,
        uint256 trxReturned
    );


    /*
        Emitted when accumulated minting fees are withdrawn.
    */
    event FeesWithdrawn(
        address indexed recipient,
        uint256 amount
    );


    /*
        ============================================================
        CONSTRUCTOR
        ============================================================
    */


    /*
        Creates the MHUSD token.

        `initialOwner`

            Your TRON wallet.

        This wallet becomes the administrator of the protocol.

        IMPORTANT:

            The oracle is intentionally NOT set in the constructor
            because the current official oracle proxy address must
            be verified before deployment.

            After deployment:

                setPriceFeed(OFFICIAL_TRX_USD_FEED)
    */
    constructor(address initialOwner)
        TRC20(
            "Muhammadreza Haghiri's USD",
            "MHUSD"
        )
        Ownable(initialOwner)
        TRC20Permit(
            "Muhammadreza Haghiri's USD"
        )
    {
        /*
            No oracle has been configured yet.
        */
        priceFeed =
            AggregatorV3Interface(address(0));

        /*
            No price exists yet.
        */
        trxUsdPrice = 0;

        /*
            No price update has occurred.
        */
        priceUpdatedAt = 0;
    }


    /*
        ============================================================
        ORACLE CONFIGURATION
        ============================================================
    */


    /*
        Sets the TRX/USD oracle.

        ONLY THE OWNER CAN CALL THIS FUNCTION.

        `_feed`

            Address of the official TRX/USD oracle proxy.

        Recommended source:

            WINkLink TRON price-feed documentation.

        The oracle follows the standard:

            AggregatorV3Interface

        After this is configured, the contract automatically
        reads TRX/USD.

        There is no longer a `setTRXUSDPrice()` function.
    */
    function setPriceFeed(
        address _feed
    )
        external
        onlyOwner
    {
        /*
            Reject the zero address.

            A zero address would make oracle calls impossible.
        */
        require(
            _feed != address(0),
            "Invalid price feed"
        );

        /*
            Store the old feed for the event.
        */
        address oldFeed =
            address(priceFeed);

        /*
            Set the new oracle.
        */
        priceFeed =
            AggregatorV3Interface(_feed);

        /*
            Notify external applications.
        */
        emit PriceFeedUpdated(
            oldFeed,
            _feed
        );
    }


    /*
        ============================================================
        ORACLE PRICE READING
        ============================================================
    */


    /*
        Reads the latest TRX/USD price directly from the oracle.

        This function is VIEW-only.

        It does not modify blockchain state.

        The returned price is normalized to 8 decimals.

        Example:

            Oracle returns:

                answer = 30000000
                decimals = 8

            Result:

                $0.30
    */
    function getLatestTRXUSDPrice()
        public
        view
        returns (
            uint256 price,
            uint256 updatedAt
        )
    {
        /*
            Make sure an oracle has been configured.
        */
        require(
            address(priceFeed) != address(0),
            "Price feed not configured"
        );

        /*
            Ask the oracle for its latest round.
        */
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 _updatedAt,
            uint80 answeredInRound
        ) =
            priceFeed.latestRoundData();

        /*
            The oracle must have returned a valid round.
        */
        require(
            roundId > 0,
            "Invalid oracle round"
        );

        /*
            Price must be positive.

            A zero or negative price cannot be used.
        */
        require(
            answer > 0,
            "Invalid oracle price"
        );

        /*
            The round must actually have been answered.
        */
        require(
            answeredInRound >= roundId,
            "Incomplete oracle round"
        );

        /*
            The oracle must provide a valid update timestamp.
        */
        require(
            _updatedAt > 0,
            "Invalid oracle timestamp"
        );

        /*
            The price must not be older than MAX_PRICE_AGE.

            This protects users from an extremely stale price.
        */
        require(
            block.timestamp >= _updatedAt,
            "Invalid future timestamp"
        );

        require(
            block.timestamp - _updatedAt
                <= MAX_PRICE_AGE,
            "Stale oracle price"
        );

        /*
            The oracle may use a different number of decimals.

            We normalize it to exactly 8 decimals.
        */
        uint8 feedDecimals =
            priceFeed.decimals();

        uint256 unsignedAnswer =
            uint256(answer);

        /*
            Convert the oracle value to 8 decimals.

            Example:

                Oracle decimals = 8

                No conversion required.

                Oracle decimals = 18

                Divide by 10^10.

                Oracle decimals = 6

                Multiply by 10^2.
        */
        if (feedDecimals < 8) {

            price =
                unsignedAnswer
                *
                (10 ** (8 - feedDecimals));

        } else if (feedDecimals > 8) {

            price =
                unsignedAnswer
                /
                (10 ** (feedDecimals - 8));

        } else {

            price =
                unsignedAnswer;
        }

        /*
            Make sure normalization did not produce zero.
        */
        require(
            price > 0,
            "Normalized price is zero"
        );

        /*
            Return the timestamp supplied by the oracle.
        */
        updatedAt = _updatedAt;

        /*
            Silence compiler warnings for the timestamp variable
            returned by some oracle implementations.

            `startedAt` is intentionally not used because
            `updatedAt` is the relevant freshness timestamp.
        */
        startedAt;
    }


    /*
        ============================================================
        INTERNAL PRICE UPDATE
        ============================================================
    */


    /*
        Reads the current price from the oracle and stores it
        in contract state.

        This is called automatically during mint/redeem operations.

        Users therefore do NOT need to manually update the price.

        The function is internal because users should not need
        to call a separate price-update transaction.
    */
    function _updatePrice()
        internal
        returns (uint256 price)
    {
        /*
            Read the current oracle price.
        */
        uint256 oldPrice =
            trxUsdPrice;

        uint256 updatedAt;

        (
            price,
            updatedAt
        ) =
            getLatestTRXUSDPrice();

        /*
            Store the latest oracle price.

            This does not create the price.

            It only caches the oracle's actual price for
            transparency and frontend convenience.
        */
        trxUsdPrice =
            price;

        /*
            Store the oracle's timestamp.
        */
        priceUpdatedAt =
            updatedAt;

        /*
            Emit the price change.
        */
        emit PriceUpdated(
            oldPrice,
            price,
            updatedAt
        );
    }


    /*
        ============================================================
        PRICE INFORMATION
        ============================================================
    */


    /*
        Returns the current TRX/USD price directly from the oracle.

        This is the function frontends can call to display
        the current price.
    */
    function getTRXUSDPrice()
        external
        view
        returns (uint256)
    {
        (
            uint256 price,

        ) =
            getLatestTRXUSDPrice();

        return price;
    }


    /*
        Returns the last price cached by a successful mint/redeem
        operation.

        This does not contact the oracle.
    */
    function getCachedTRXUSDPrice()
        external
        view
        returns (uint256)
    {
        return trxUsdPrice;
    }


    /*
        Returns the oracle's address.
    */
    function getPriceFeed()
        external
        view
        returns (address)
    {
        return address(priceFeed);
    }


    /*
        ============================================================
        PRICE CONVERSION
        ============================================================
    */


    /*
        Calculates how much TRX is required to represent a given
        amount of MHUSD.

        Example:

            TRX/USD = $0.30

            1 MHUSD = $1

            Required:

                3.333333 TRX
    */
    function getTRXRequiredForMHUSD(
        uint256 _mhusdAmount
    )
        public
        view
        returns (uint256)
    {
        /*
            Obtain the current oracle price.

            This means this calculation uses the live oracle price
            rather than the manually entered historical price.
        */
        uint256 price =
            _getCurrentPrice();

        /*
            Convert 18-decimal MHUSD into 6-decimal TRX.

            Formula:

                TRX =
                    MHUSD
                    ×
                    1e6
                    ×
                    1e8
                    /
                    1e18
                    /
                    TRX/USD
        */
        return
            (
                _mhusdAmount
                *
                1e6
                *
                PRICE_PRECISION
            )
            /
            (
                1e18
                *
                price
            );
    }


    /*
        Calculates how much MHUSD corresponds to a given amount
        of TRX.

        `_trxAmount`

            TRX amount in SUN.
    */
    function getMHUSDForTRX(
        uint256 _trxAmount
    )
        public
        view
        returns (uint256)
    {
        /*
            Read the current oracle price.
        */
        uint256 price =
            _getCurrentPrice();

        /*
            Convert TRX into USD and then USD into MHUSD.
        */
        return
            (
                _trxAmount
                *
                price
                *
                1e18
            )
            /
            (
                1e6
                *
                PRICE_PRECISION
            );
    }


    /*
        Internal helper used by view functions.

        Reads the oracle but does not modify cached state.
    */
    function _getCurrentPrice()
        internal
        view
        returns (uint256)
    {
        (
            uint256 price,

        ) =
            getLatestTRXUSDPrice();

        return price;
    }


    /*
        ============================================================
        MINT FEE
        ============================================================
    */


    /*
        Calculates the 0.05% minting fee.

        Example:

            100 TRX backing

            Fee:

                100 × 0.05%
                =
                0.05 TRX
    */
    function calculateMintFee(
        uint256 _trxBacking
    )
        public
        pure
        returns (uint256)
    {
        return
            (
                _trxBacking
                *
                MINT_FEE_BPS
            )
            /
            BASIS_POINTS;
    }


    /*
        ============================================================
        MINT
        ============================================================
    */


    /*
        Mints MHUSD by depositing TRX.

        The TRX/USD price is obtained AUTOMATICALLY from the oracle.

        The user sends:

            backing + 0.05% fee

        Example:

            TRX/USD = $0.30

            User sends approximately:

                100 TRX

            The contract calculates the current USD value using
            the oracle and mints approximately:

                $29.985 MHUSD

            depending on the exact fee/rounding.

        No manual price input is required.
    */
    function mint()
        external
        payable
    {
        /*
            The caller must send TRX.
        */
        require(
            msg.value > 0,
            "Send TRX"
        );

        /*
            IMPORTANT:

            Read the current oracle price before calculating
            the amount to mint.

            This replaces the old manual `setTRXUSDPrice()`.
        */
        uint256 price =
            _updatePrice();

        /*
            Silence the local-variable warning while making the
            dependency explicit.
        */
        price;

        /*
            Separate the user's total payment into:

                backing
                +
                minting fee

            Algebra:

                total = backing + backing * 5 / 10000

                backing =
                    total * 10000 / 10005
        */
        uint256 backingTRX =
            (
                msg.value
                *
                BASIS_POINTS
            )
            /
            (
                BASIS_POINTS
                +
                MINT_FEE_BPS
            );

        /*
            Everything not allocated to collateral becomes
            the minting fee.
        */
        uint256 fee =
            msg.value
            -
            backingTRX;

        /*
            Convert the TRX backing into MHUSD using the fresh
            oracle price.
        */
        uint256 amountToMint =
            getMHUSDForTRX(
                backingTRX
            );

        /*
            Do not allow a zero-token mint.
        */
        require(
            amountToMint > 0,
            "Amount too small"
        );

        /*
            Record user collateral.
        */
        totalBackingTRX +=
            backingTRX;

        /*
            Record protocol fees.
        */
        accumulatedMintFees +=
            fee;

        /*
            Create the MHUSD.
        */
        _mint(
            msg.sender,
            amountToMint
        );

        /*
            Emit the mint event.
        */
        emit MHUSDMinted(
            msg.sender,
            backingTRX,
            fee,
            amountToMint
        );
    }


    /*
        ============================================================
        REDEEM
        ============================================================
    */


    /*
        Burns MHUSD and returns the current TRX value.

        Example:

            User redeems:

                30 MHUSD

            If TRX/USD = $0.30:

                30 / 0.30
                =
                100 TRX

            The 30 MHUSD is burned.

            Approximately 100 TRX is returned.

        The current oracle price is used automatically.
    */
    function redeem(
        uint256 _mhusdAmount
    )
        external
    {
        /*
            The user must redeem a positive amount.
        */
        require(
            _mhusdAmount > 0,
            "Amount is zero"
        );

        /*
            Obtain a fresh oracle price.

            This means redemption is never based on an old
            manually-entered price.
        */
        uint256 price =
            _updatePrice();

        /*
            Silence unused-variable warning.
        */
        price;

        /*
            Calculate the current TRX value.
        */
        uint256 trxToReturn =
            getTRXRequiredForMHUSD(
                _mhusdAmount
            );

        /*
            The requested redemption cannot exceed the recorded
            user collateral.
        */
        require(
            trxToReturn <= totalBackingTRX,
            "Insufficient backing"
        );

        /*
            The contract must physically have enough TRX.
        */
        require(
            address(this).balance
                >= trxToReturn,
            "Insufficient TRX"
        );

        /*
            Burn the user's MHUSD.
        */
        _burn(
            msg.sender,
            _mhusdAmount
        );

        /*
            Reduce recorded collateral.
        */
        totalBackingTRX -=
            trxToReturn;

        /*
            Return the corresponding TRX.
        */
        (bool success, ) =
            payable(msg.sender).call{
                value: trxToReturn
            }("");

        /*
            If TRX transfer fails, revert everything.
        */
        require(
            success,
            "TRX transfer failed"
        );

        /*
            Emit redemption information.
        */
        emit MHUSDRedeemed(
            msg.sender,
            _mhusdAmount,
            trxToReturn
        );
    }


    /*
        ============================================================
        REDEMPTION PREVIEW
        ============================================================
    */


    /*
        Shows how much TRX the user would receive for a given
        MHUSD amount using the CURRENT oracle price.

        This is useful for wallets and frontends.
    */
    function previewRedeem(
        uint256 _mhusdAmount
    )
        external
        view
        returns (uint256)
    {
        return
            getTRXRequiredForMHUSD(
                _mhusdAmount
            );
    }


    /*
        ============================================================
        VAULT INFORMATION
        ============================================================
    */


    /*
        Returns the amount of TRX recorded as user backing.
    */
    function backingTRX()
        external
        view
        returns (uint256)
    {
        return totalBackingTRX;
    }


    /*
        Returns accumulated minting fees.
    */
    function mintFees()
        external
        view
        returns (uint256)
    {
        return accumulatedMintFees;
    }


    /*
        Returns the actual TRX balance held by this contract.

        This includes:

            backing
            +
            fees
            +
            any additional TRX sent directly to the contract.
    */
    function vaultBalance()
        external
        view
        returns (uint256)
    {
        return address(this).balance;
    }


    /*
        ============================================================
        FEE WITHDRAWAL
        ============================================================
    */


    /*
        Withdraws accumulated minting fees.

        ONLY THE OWNER CAN CALL THIS.

        The owner cannot use this function to withdraw
        `totalBackingTRX`.

        Only the amount explicitly recorded as fees is withdrawn.
    */
    function withdrawMintFees(
        address payable recipient
    )
        external
        onlyOwner
    {
        /*
            Reject zero address.
        */
        require(
            recipient != address(0),
            "Invalid recipient"
        );

        /*
            Read accumulated fees.
        */
        uint256 amount =
            accumulatedMintFees;

        /*
            There must be something to withdraw.
        */
        require(
            amount > 0,
            "No fees"
        );

        /*
            Effects before interaction.

            This prevents reentrancy-style accounting problems.
        */
        accumulatedMintFees = 0;

        /*
            Transfer the fees to the recipient.
        */
        (bool success, ) =
            recipient.call{
                value: amount
            }("");

        /*
            Revert if the transfer failed.
        */
        require(
            success,
            "Fee transfer failed"
        );

        /*
            Emit withdrawal event.
        */
        emit FeesWithdrawn(
            recipient,
            amount
        );
    }


    /*
        ============================================================
        COLLATERAL CHECK
        ============================================================
    */


    /*
        Checks whether the physical TRX balance is at least equal
        to the recorded backing.

        Returns:

            true
                Contract has enough TRX.

            false
                Contract balance is below recorded backing.
    */
    function isCollateralized()
        external
        view
        returns (bool)
    {
        return
            address(this).balance
            >=
            totalBackingTRX;
    }


    /*
        ============================================================
        RECEIVE TRX
        ============================================================
    */


    /*
        Allows the contract to receive plain TRX transfers.

        IMPORTANT:

            A plain TRX transfer does NOT automatically create
            MHUSD and does NOT increase `totalBackingTRX`.

        Users should use `mint()` when they want to mint MHUSD.
    */
    receive()
        external
        payable
    {
        /*
            Intentionally empty.

            TRX is accepted but not treated as new collateral.
        */
    }
}