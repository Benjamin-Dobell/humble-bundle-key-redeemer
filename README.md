# Humble Bundle Key Redeemer

Automatically redeems Humble Bundle keys visible in your browser's active tab using the Steam client installed on your computer.

Inspired by [steamkeyactivator](https://github.com/google/steamkeysactivator).

## What problems does this solve?

Firstly, no-one likes to manually copy and paste keys over and over from their web browser, particularly given how many clicks it takes to activate just one key in Steam!

However, what sets this project apart from similar projects is that we do our best to avoid prematurely hitting Steam's key redemption rate-limit.

## What is Steam's key redemption rate limit?

Basically Steam only allows a certain number of key redemption _attempts_ per hour, this is designed to stop people brute-force guessing Steam keys.

You're only allowed around 25 key redemption attempts each hour. That isn't a lot if you've purchased a few Humble Bundles. However, it's a real issue if your key redemption attempts fail, Steam will lock you out much quicker. That doesn't seem unreasonable, however Steam considers two common scenarios as failures:

 1. Accidentally attempting to redeem a key you've already redeemed.
 2. Redeem a key that has never before been redeemed, _but_ is for a game you already own.

The former is annoying, but the latter is a real issue, particularly with Humble Bundles, as it's fairly common for the one game to appear in multiple bundles.

## What does this key redeemer do that's special?

Aside from being a bit more clever than most (displaying things like game names), this redeemer does several things to try mitigate the two issues describes above. It does this two ways.

Firstly, by keeping a record of all the keys that have previously been redeemed, or failed to be redeemed.

Secondly, by looking at your Steam accounts list of activations, and cross-referencing the names of the games (and DLC etc.) on the Humble Bundle website against them. Unfortunately, Humble Bundle doesn't use the exact same titles as Steam, so we try to be clever about it and look for _similarly_ named items that you already own, and skip activating those keys.

## How does it work?

We presently require that you use OS X, and that you use either Chrome of Safari.

You navigate to a Humble Bundle page with some keys visible that you'd like activated. Then you run the Humble Bundle Key Activator. It'll automatically detect your browser and find the Humble Bundle keys visible in your active tab. Then as described above, we automatically cross-reference these keys/titles against titles you already own - you'll be prompted to login to Steam via your browser if you aren't already.

We then use your local Steam client to activate these keys in a similar fashion to how you would do so manually. You'll literally see the Steam user interface automatically being interacted with.

__Don't touch your keyboard or mouse while this is happening.__

When all the keys have been activated you'll be notified (it's _much_ quicker than doing it by hand) and a record will be kept with regards to which keys were redeemed, which ones were unredeemed (possibly suitable for gifting to friends) and which keys failed to be redeemed (ideally none).

## How to run the Humble Bundle Key Redeemer

At the moment it's just a simple Ruby script. So you'll need to install some dependencies.

### Installing Ruby

OS X does come with a Ruby interpreter, but it's the "system Ruby" and you can't easily install dependencies (Gems).

There's a few solutions, ideally you'll use a Ruby version manager. However, if you don't know what that is (or care), then the simplest solutions is just to install Ruby from [Homebrew](https://brew.sh/):

```
brew install ruby
```

### Installing the script dependencies

```
gem install bundler
bundle install
```

### Run the script

```
./humble-bundle-key-redeemer.rb
```

