// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin TRON Contracts ^5.6.0
pragma solidity ^0.8.26;

/*
    ================================================================
    MHUSD - Muhammadreza Haghiri USD
    ================================================================

    Target:
        1 MHUSD = 1 USD

    Blockchain:
        TRON

    Standard:
        TRC-20

    Mechanism:
        - Users deposit TRX.
        - The contract uses an admin-controlled TRX/USD price.
        - The user receives exactly $1 worth of MHUSD for every
          $1 worth of TRX deposited.
        - A 0.05% minting fee is charged.
        - The minting fee remains in the contract.
        - On redemption, MHUSD is burned.
        - The user receives the TRX value represented by the
          redeemed MHUSD according to the current price.
        - No redemption fee is charged.

    IMPORTANT:

        This is a collateralized stablecoin mechanism, not a
        mathematically guaranteed USD peg.

        The contract cannot independently know the market price
        of TRX/USD. The owner must update the TRX/USD price.

        Therefore:

            price feed accuracy
                +
            sufficient TRX collateral
                +
            functioning redemption
                =
            ability to maintain the target price

        For a production stablecoin, the owner-controlled price
        feed should eventually be replaced with a decentralized
        oracle system.

    ================================================================
*/

import {Ownable} from "@openzeppelin/tron-contracts/access/Ownable.sol";
import {TRC20} from "@openzeppelin/tron-contracts/token/TRC20/TRC20.sol";
import {TRC20Burnable} from "@openzeppelin/tron-contracts/token/TRC20/extensions/TRC20Burnable.sol";
import {TRC20Permit} from "@openzeppelin/tron-contracts/token/TRC20/extensions/TRC20Permit.sol";


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
        Basis-point denominator.

        10,000 basis points = 100%.

        Therefore:

            5 / 10,000 = 0.05%

        The minting fee is consequently 5 basis points.
    */
    uint256 public constant BASIS_POINTS = 10_000;


    /*
        Minting fee.

        5 basis points = 0.05%.

        Example:

            User deposits 100 TRX worth of value.

            Fee:
                100 * 0.05% = 0.05 TRX

            Backing:
                100 TRX

            Total sent:
                100.05 TRX
    */
    uint256 public constant MINT_FEE_BPS = 5;


    /*
        Price precision.

        TRX/USD prices are represented using 8 decimal places.

        Example:

            TRX = $0.25

        is represented as:

            25,000,000
    */
    uint256 public constant PRICE_PRECISION = 1e8;


    /*
        Minimum allowed TRX/USD price.

        Prevents accidental division by zero.
    */
    uint256 public constant MIN_TRX_USD_PRICE = 1;


    /*
        Maximum allowed TRX/USD price.

        This is simply a safety boundary against accidentally
        entering an absurd value into the price feed.

        It can be increased later if necessary.
    */
    uint256 public constant MAX_TRX_USD_PRICE = 1_000_000_000_000;


    /*
        ============================================================
        STATE VARIABLES
        ============================================================
    */

    /*
        Current TRX price expressed in USD.

        Example:

            If 1 TRX = $0.30

            trxUsdPrice = 30,000,000

        because the price has 8 decimal places.
    */
    uint256 public trxUsdPrice;


    /*
        Timestamp of the most recent price update.

        Applications can use this to determine how fresh
        the price feed is.
    */
    uint256 public priceUpdatedAt;


    /*
        Total amount of TRX that represents user backing.

        This tracks the principal deposited for minted MHUSD.

        It does NOT include accumulated minting fees.
    */
    uint256 public totalBackingTRX;


    /*
        Total amount of minting fees accumulated by the protocol.

        These TRX remain inside the contract until withdrawn
        by the owner.
    */
    uint256 public accumulatedMintFees;


    /*
        ============================================================
        EVENTS
        ============================================================
    */


    /*
        Emitted whenever the TRX/USD price is changed.
    */
    event PriceUpdated(
        uint256 oldPrice,
        uint256 newPrice,
        uint256 timestamp
    );


    /*
        Emitted whenever MHUSD is minted.

        `user`
            The account receiving MHUSD.

        `trxBacking`
            TRX deposited as backing.

        `fee`
            Minting fee paid by the user.

        `mhusdMinted`
            Number of MHUSD tokens created.
    */
    event MHUSDMinted(
        address indexed user,
        uint256 trxBacking,
        uint256 fee,
        uint256 mhusdMinted
    );


    /*
        Emitted whenever MHUSD is redeemed.

        `user`
            Account receiving TRX.

        `mhusdBurned`
            Number of MHUSD destroyed.

        `trxReturned`
            TRX returned to the user.
    */
    event MHUSDRedeemed(
        address indexed user,
        uint256 mhusdBurned,
        uint256 trxReturned
    );


    /*
        Emitted whenever accumulated protocol fees are withdrawn.
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
        Constructor.

        `initialOwner`
            The TRON wallet that becomes the administrator.

        Deploy the contract with YOUR wallet address here.

        Example:

            constructor(TYOUR_WALLET_ADDRESS)

        The wallet becomes the OpenZeppelin Ownable owner and
        therefore controls the administrative functions.
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
            We initialize the price at zero.

            The owner must call `setTRXUSDPrice()` before anyone
            can mint or redeem.
        */
        trxUsdPrice = 0;

        /*
            No price has been published yet.
        */
        priceUpdatedAt = 0;
    }


    /*
        ============================================================
        PRICE ORACLE / PRICE ADMINISTRATION
        ============================================================
    */


    /*
        Set the current TRX/USD price.

        ONLY THE OWNER CAN CALL THIS FUNCTION.

        `_price`

            TRX price in USD with 8 decimal places.

            Examples:

                $0.10
                    10,000,000

                $0.25
                    25,000,000

                $0.50
                    50,000,000

                $1.00
                    100,000,000

        Why this exists:

            Solidity cannot magically know the current USD price
            of TRX.

            This function acts as the price-feed interface.

        IMPORTANT:

            For a real production stablecoin, this should ideally
            be replaced by a decentralized oracle rather than
            relying on a single administrator.
    */
    function setTRXUSDPrice(
        uint256 _price
    )
        external
        onlyOwner
    {
        /*
            Reject zero or unreasonable values.
        */
        require(
            _price >= MIN_TRX_USD_PRICE,
            "Invalid price"
        );

        require(
            _price <= MAX_TRX_USD_PRICE,
            "Price too high"
        );

        /*
            Save the previous price for the event.
        */
        uint256 oldPrice = trxUsdPrice;

        /*
            Update the current TRX/USD price.
        */
        trxUsdPrice = _price;

        /*
            Record when the price was updated.
        */
        priceUpdatedAt = block.timestamp;

        /*
            Tell off-chain applications that the price changed.
        */
        emit PriceUpdated(
            oldPrice,
            _price,
            block.timestamp
        );
    }


    /*
        Returns the current TRX/USD price.

        This is a view-only helper.

        It does not modify blockchain state and therefore does
        not require a transaction.
    */
    function getTRXUSDPrice()
        external
        view
        returns (uint256)
    {
        return trxUsdPrice;
    }


    /*
        ============================================================
        PRICE CONVERSION FUNCTIONS
        ============================================================
    */


    /*
        Calculate how much TRX is required to mint a given amount
        of MHUSD.

        `_mhusdAmount`

            Amount of MHUSD expressed in the token's 18 decimals.

        Returns:

            Number of SUN/TRX units required as backing.

        Example:

            TRX = $0.25

            Minting:

                1 MHUSD

            requires:

                4 TRX

        because:

                4 TRX * $0.25 = $1
    */
    function getTRXRequiredForMHUSD(
        uint256 _mhusdAmount
    )
        public
        view
        returns (uint256)
    {
        require(
            trxUsdPrice > 0,
            "Price not initialized"
        );

        /*
            MHUSD has 18 decimals.

            TRX has 6 decimals.

            We therefore convert between the two decimal systems.

            Formula:

                TRX =
                    MHUSD amount
                    *
                    1e6
                    *
                    1e8
                    /
                    1e18
                    /
                    TRX/USD price
        */

        return
            (_mhusdAmount * 1e6 * PRICE_PRECISION)
            /
            (1e18 * trxUsdPrice);
    }


    /*
        Calculate how much MHUSD can be minted from a given amount
        of TRX backing.

        `_trxAmount`

            TRX amount expressed in SUN.

        Returns:

            MHUSD amount expressed with 18 decimals.
    */
    function getMHUSDForTRX(
        uint256 _trxAmount
    )
        public
        view
        returns (uint256)
    {
        require(
            trxUsdPrice > 0,
            "Price not initialized"
        );

        /*
            Convert TRX into USD and then USD into MHUSD.
        */
        return
            (_trxAmount * trxUsdPrice * 1e18)
            /
            (1e6 * PRICE_PRECISION);
    }


    /*
        Calculate the minting fee for a given amount of backing.

        `_trxBacking`

            TRX that will become collateral.

        Returns:

            Fee in SUN.
    */
    function calculateMintFee(
        uint256 _trxBacking
    )
        public
        pure
        returns (uint256)
    {
        /*
            0.05% = 5 / 10,000.
        */
        return
            (_trxBacking * MINT_FEE_BPS)
            /
            BASIS_POINTS;
    }


    /*
        ============================================================
        MINT
        ============================================================
    */


    /*
        Mint MHUSD by depositing TRX.

        The caller sends TRX with the transaction.

        The amount sent consists of:

            backing + 0.05% minting fee

        Example:

            TRX/USD = $0.25

            User wants:

                100 MHUSD

            Required backing:

                400 TRX

            Mint fee:

                400 * 0.05%
                = 0.2 TRX

            User sends:

                400.2 TRX

            User receives:

                100 MHUSD

            400 TRX becomes backing.

            0.2 TRX becomes protocol fee.

        The fee remains in this contract.

        The caller receives the newly minted MHUSD.
    */
    function mint()
        external
        payable
    {
        /*
            A price must exist before minting.
        */
        require(
            trxUsdPrice > 0,
            "Price not initialized"
        );

        /*
            The transaction must contain TRX.
        */
        require(
            msg.value > 0,
            "Send TRX"
        );

        /*
            Determine the minting fee.

            Since the fee is 0.05%, we solve:

                total = backing + fee

            where:

                fee = backing * 5 / 10000

            Therefore:

                total = backing * 10005 / 10000

            So:

                backing = total * 10000 / 10005
        */
        uint256 backingTRX =
            (msg.value * BASIS_POINTS)
            /
            (BASIS_POINTS + MINT_FEE_BPS);

        /*
            Everything left over becomes the minting fee.
        */
        uint256 fee =
            msg.value - backingTRX;

        /*
            Convert the backing amount of TRX into MHUSD.
        */
        uint256 amountToMint =
            getMHUSDForTRX(backingTRX);

        /*
            Rounding should never result in zero tokens.
        */
        require(
            amountToMint > 0,
            "Amount too small"
        );

        /*
            Increase protocol accounting for collateral.
        */
        totalBackingTRX += backingTRX;

        /*
            Increase protocol accounting for fees.
        */
        accumulatedMintFees += fee;

        /*
            Create the MHUSD tokens.

            `_mint` is inherited from OpenZeppelin TRC20.
        */
        _mint(
            msg.sender,
            amountToMint
        );

        /*
            Emit a transparent record of the operation.
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
        Redeem MHUSD for TRX.

        The caller specifies how many MHUSD tokens they want
        to redeem.

        Example:

            User owns:

                100 MHUSD

            Current TRX price:

                $0.25

            Therefore:

                100 MHUSD = $100
                          = 400 TRX

            The contract:

                1. Burns 100 MHUSD.
                2. Reduces backing by 400 TRX.
                3. Sends 400 TRX to the user.

        IMPORTANT:

            This assumes the contract has enough TRX collateral.

            The protocol cannot pay more TRX than it actually
            holds.
    */
    function redeem(
        uint256 _mhusdAmount
    )
        external
    {
        /*
            A price must exist.
        */
        require(
            trxUsdPrice > 0,
            "Price not initialized"
        );

        /*
            User must specify a positive amount.
        */
        require(
            _mhusdAmount > 0,
            "Amount is zero"
        );

        /*
            Calculate the TRX value represented by the tokens.
        */
        uint256 trxToReturn =
            getTRXRequiredForMHUSD(
                _mhusdAmount
            );

        /*
            Make sure the contract has sufficient backing.

            This is the fundamental solvency check.
        */
        require(
            trxToReturn <= totalBackingTRX,
            "Insufficient backing"
        );

        /*
            Make sure the contract actually has enough TRX
            available to perform the transfer.

            Minting fees are intentionally excluded from
            `totalBackingTRX`, so they are not supposed to be
            required to satisfy ordinary redemptions.
        */
        require(
            address(this).balance >= trxToReturn,
            "Insufficient TRX"
        );

        /*
            Burn the user's MHUSD.

            `_burn` removes the tokens permanently.
        */
        _burn(
            msg.sender,
            _mhusdAmount
        );

        /*
            Reduce the recorded collateral.
        */
        totalBackingTRX -= trxToReturn;

        /*
            Transfer the corresponding TRX back to the user.

            TRON's TVM supports ordinary value transfers through
            the normal payable call mechanism.
        */
        (bool success, ) =
            payable(msg.sender).call{
                value: trxToReturn
            }("");

        /*
            If the transfer fails, revert the entire transaction.

            This also means the token burn and accounting changes
            are reverted.
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
        Allows wallets and frontends to calculate how much TRX
        a user would receive before actually redeeming.

        This function does not modify state.
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
        Returns the amount of TRX currently recorded as backing.

        This is the principal collateral amount and excludes
        accumulated minting fees.
    */
    function backingTRX()
        external
        view
        returns (uint256)
    {
        return totalBackingTRX;
    }


    /*
        Returns the amount of accumulated minting fees.

        These fees are held by the contract.
    */
    function mintFees()
        external
        view
        returns (uint256)
    {
        return accumulatedMintFees;
    }


    /*
        Returns the total TRX physically held by the contract.

        This includes:

            backing TRX
            +
            accumulated fees
            +
            any other TRX accidentally sent to the contract
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
        PROTOCOL FEE WITHDRAWAL
        ============================================================
    */


    /*
        Withdraw accumulated minting fees.

        ONLY THE OWNER CAN CALL THIS.

        IMPORTANT:

            The owner is only allowed to withdraw the amount
            recorded as accumulated fees.

            User backing cannot be withdrawn through this
            function.

        This separation is important because the contract's
        solvency depends on preserving backing.
    */
    function withdrawMintFees(
        address payable recipient
    )
        external
        onlyOwner
    {
        /*
            Recipient must be a valid address.
        */
        require(
            recipient != address(0),
            "Invalid recipient"
        );

        /*
            Capture the fee amount.
        */
        uint256 amount =
            accumulatedMintFees;

        /*
            There must be fees available.
        */
        require(
            amount > 0,
            "No fees"
        );

        /*
            Reset the accounting BEFORE sending TRX.

            This follows the checks-effects-interactions pattern.
        */
        accumulatedMintFees = 0;

        /*
            Send only the protocol fees.

            User collateral remains untouched.
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
            Emit a transparent record.
        */
        emit FeesWithdrawn(
            recipient,
            amount
        );
    }


    /*
        ============================================================
        EMERGENCY FUNCTION
        ============================================================
    */


    /*
        Returns whether the contract is currently sufficiently
        collateralized according to its internal accounting.

        This is a view function and does not modify anything.

        A healthy result means:

            actual TRX balance >= recorded backing
    */
    function isCollateralized()
        external
        view
        returns (bool)
    {
        return
            address(this).balance >= totalBackingTRX;
    }


    /*
        ============================================================
        RECEIVE TRX
        ============================================================
    */


    /*
        Allows the contract to receive TRX through a plain transfer.

        This TRX is NOT automatically counted as user backing.

        For proper minting, users should use `mint()`.

        Plain TRX transfers are therefore treated as extra
        contract balance.
    */
    receive()
        external
        payable
    {
        /*
            Intentionally empty.

            TRX is accepted by the contract but is not added to
            `totalBackingTRX`.
        */
    }
}