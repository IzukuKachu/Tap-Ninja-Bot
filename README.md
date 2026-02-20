# Tap-Ninja-Bot
Tap Ninja Bot/Script/Auto Clicker made using AutohotkeyV2 
This bot was made with Tap Ninja in 1920x1080 Windowed Borderless mode.

I have only made it as far as Shieldbearer, Shuriken Vortex has not been unlocked for me yet.

Shuriken Vortex has been added to the UI/Bot logic, but I am unsure if it does or doesn't work, if it does work, I am not sure if it will interfere with any other actions.

House purchase is set to buy the second from last house currently, I had a version that would purchase anything that turned green, but this made afk farming take longer. Maybe there is some logic we can use to occasionally use the purchase any that are green option, but I have not had time to figure out what would be the best way about doing this.

Page swap between House/Upgrades is set at 15000ms (15 Seconds)

Pixel detection for page swap determines what page the bot thinks it's on, the way I set this up to work, is if the page is on Upgrades, the darkest blue pixel of the mana bottle is detected, if the pixel does not match, it determines it is on the House purchasing page. (If you need to fix the page swap mechanic, make sure the page you are on is selected before you use the Pick tool within the settings to pick what pixel your bot will be checking.)

Fly detection takes priority over all other clicks/actions, I have not implemented a way to turn off Fly detection/Clicks, if this is something you are interested in, you are going to have to ask me to implement it, cause I don't see a reason for me to do that currently if left to my own devices.
Shuriken/Rope Hook timing must be altered within the Timing section of the settings tab (or within the .ini file) to match what your personal cooldown is, I have no upgrades, so my 20 Second cool down translates to 20,000ms, which is what the bot is set too currently.

Fireflies/Enemies may be added within the Settings menu, the easiest way I have found so far is to screenshot the enemy/fly that you need, open paint, and use the Pick tool to determine the color you want the bot to click. For Fireflys I use the colored outline around the fly itself (not the outline of the circle) I'll leave an image of the Sakura Fly, with a circle outlining which pixel I am talking about.

![Tap Ninja BotUI](https://github.com/user-attachments/assets/dc83ee75-88d7-44a6-9052-8e39998cd282)
![Tap Ninja Bot Fly](https://github.com/user-attachments/assets/6f56f117-08bd-4ea4-8050-15f73a49d45f)
![Tap Ninja Fly](https://github.com/user-attachments/assets/02c5145a-98cc-4950-9d43-1a598be24115)

