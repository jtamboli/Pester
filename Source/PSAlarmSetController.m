//
//  PSAlarmSetController.m
//  Pester
//
//  Created by Nicholas Riley on Tue Oct 08 2002.
//  Copyright (c) 2002 Nicholas Riley. All rights reserved.
//

#import "PSAlarmSetController.h"
#import "PSAlarmNotifierController.h"
#import "NJRDateFormatter.h"

// XXX Bugs to file:
// XXX any trailing spaces: -> exception for +[NSCalendarDate dateWithNaturalLanguageString]:
// > NSCalendarDate dateWithNaturalLanguageString: '12 '
// format error: internal error

// XXX NSDate natural language stuff in NSCalendarDate (why?), misspelled category name
// XXX NSCalendarDate natural language stuff behaves differently from NSDateFormatter (AM/PM has no effect, shouldn't they share code?)
// XXX NSDateFormatter doc class description gives two examples for natural language that are incorrect, no link to NSDate doc that describes exactly how natural language dates are parsed
// XXX NSTimeFormatString does not include %p when it should, meaning that AM/PM is stripped yet 12-hour time is still used
// XXX NSNextDayDesignations, NSNextNextDayDesignations are noted as 'a string' in NSUserDefaults docs, but maybe they are actually an array, or either an array or a string, given their names?
// XXX "Setting the Format for Dates" does not document how to get 1:15 AM, the answer is %1I - strftime has no exact equivalent; the closest is %l.  strftime does not permit numeric prefixes.  It also refers to "NSCalendar" when no such class exists.
// XXX none of many mentions of NSAMPMDesignation indicates that they include the leading spaces (" AM", " PM").  In "Setting the Format for Dates", needs to mention that the leading spaces are not included in %p with strftime.
// XXX descriptions for %X and %x are reversed (time zone is in %X, not %x)
// XXX too hard to implement date-only or time-only formatters
// XXX should be able to specify that natural language favors date or time (10 = 10th of month, not 10am)
// XXX please expose the iCal controls!

@interface PSAlarmSetController (Private)

- (void)_stopUpdateTimer;

@end

@implementation PSAlarmSetController

- (void)awakeFromNib;
{
    // XXX bugs prevent this code from working properly on Jaguar
    /* NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [timeOfDay setFormatter: [[NJRDateFormatter alloc] initWithDateFormat: [defaults objectForKey: NSTimeFormatString] allowNaturalLanguage: YES]];
    [timeDate setFormatter: [[NJRDateFormatter alloc] initWithDateFormat: [defaults objectForKey: NSShortDateFormatString] allowNaturalLanguage: YES]]; */
    alarm = [[PSAlarm alloc] init];
    [[self window] center];
    [self inAtChanged: nil];
    [[self window] makeKeyAndOrderFront: nil];
}

- (void)setStatus:(NSString *)aString;
{
    // NSLog(@"%@", alarm);
    if (aString != status) {
        [status release]; status = nil;
        status = [aString retain];
        [timeSummary setStringValue: status];
    }
}

- (id)objectValueForTextField:(NSTextField *)field whileEditing:(id)sender;
{
    if (sender == field) {
        NSString *stringValue = [[[self window] fieldEditor: NO forObject: field] string];
        id obj = nil;
        [[field formatter] getObjectValue: &obj forString: stringValue errorDescription: NULL];
        // NSLog(@"from field editor: %@", obj);
        return obj;
    } else {
        // NSLog(@"from field: %@", [field objectValue]);
        return [field objectValue];
    }
}

- (void)setAlarmDateAndInterval:(id)sender;
{
    if (isInterval) {
        [alarm setInterval:
            [[self objectValueForTextField: timeInterval whileEditing: sender] intValue] *
                [timeIntervalUnits selectedTag]];
    } else {
        [alarm setForDate: [self objectValueForTextField: timeDate whileEditing: sender]
                   atTime: [self objectValueForTextField: timeOfDay whileEditing: sender]];
    }
}

- (void)_stopUpdateTimer;
{
    if ([updateTimer isValid]) [updateTimer invalidate];
    [updateTimer release]; updateTimer = nil;
}

// XXX use OACalendar?

- (IBAction)updateDateDisplay:(id)sender;
{
    // NSLog(@"updateDateDisplay: %@", sender);
    if ([alarm isValid]) {
        [self setStatus: [[alarm date] descriptionWithCalendarFormat: @"Alarm will be set for %X on %x" timeZone: nil locale: nil]];
        [setButton setEnabled: YES];
        if (updateTimer == nil || ![updateTimer isValid]) {
            // XXX this logic (and the timer) should really go into PSAlarm, to send notifications for status updates instead.  Timer starts when people are watching, stops when people aren't.
            // NSLog(@"setting timer");
            if (isInterval) {
                updateTimer = [NSTimer scheduledTimerWithTimeInterval: 1 target: self selector: @selector(updateDateDisplay:) userInfo: nil repeats: YES];
            } else {
                updateTimer = [NSTimer scheduledTimerWithTimeInterval: [alarm interval] target: self selector: @selector(updateDateDisplay:) userInfo: nil repeats: NO];
            }
            [updateTimer retain];
        }
    } else {
        [setButton setEnabled: NO];
        [self setStatus: [alarm invalidMessage]];
        [self _stopUpdateTimer];
    }
}

// Be careful not to hook up any of the text fields' actions to update: because we handle them in controlTextDidChange: instead.  If we could get the active text field somehow via public API (guess we could use controlTextDidBegin/controlTextDidEndEditing) then we'd not need to overload the update sender for this purpose.  Or, I guess, we could use another method other than update.  It should not be this hard to implement what is essentially standard behavior.  Sigh.

- (IBAction)update:(id)sender;
{
    // NSLog(@"update: %@", sender);
    [self setAlarmDateAndInterval: sender];
    [self updateDateDisplay: sender];
}

- (IBAction)inAtChanged:(id)sender;
{
    isInterval = ([inAtMatrix selectedTag] == 0);
    [timeInterval setEnabled: isInterval];
    [timeIntervalUnits setEnabled: isInterval];
    [timeOfDay setEnabled: !isInterval];
    [timeDate setEnabled: !isInterval];
    [timeDateCompletions setEnabled: !isInterval];
    if (sender != nil)
        [[self window] makeFirstResponder: isInterval ? timeInterval : timeOfDay];
    // NSLog(@"UPDATING FROM inAtChanged");
    [self update: nil];
}

- (IBAction)dateCompleted:(NSPopUpButton *)sender;
{
    [timeDate setStringValue: [sender titleOfSelectedItem]];
    [self update: sender];
}

// to ensure proper updating of interval, this should be the only method by which the window is shown (e.g. from the Alarm menu)
- (IBAction)showWindow:(id)sender;
{
    if (![[self window] isVisible]) {
        // NSLog(@"UPDATING FROM showWindow");
        [self update: self];
    }
    [super showWindow: sender];
}

- (IBAction)setAlarm:(NSButton *)sender;
{
    PSAlarmNotifierController *notifier = [PSAlarmNotifierController alloc];
    if (notifier == nil) {
        [self setStatus: @"Unable to set alarm."];
        return;
    }
    [self setAlarmDateAndInterval: sender];
    [alarm setMessage: [messageField stringValue]];
    if (![alarm setTimer]) {
        [self setStatus: [@"Unable to set alarm.  " stringByAppendingString: [alarm invalidMessage]]];
        return;
    }
    [self setStatus: [[alarm date] descriptionWithCalendarFormat: @"Alarm set for %x at %X" timeZone: nil locale: nil]];
    [[self window] close];
    [alarm release];
    alarm = [[PSAlarm alloc] init];
}

@end

@implementation PSAlarmSetController (NSControlSubclassDelegate)

- (void)control:(NSControl *)control didFailToValidatePartialString:(NSString *)string errorDescription:(NSString *)error;
{
    unichar c;
    int tag;
    unsigned length = [string length];
    if (control != timeInterval || length == 0) return;
    c = [string characterAtIndex: length - 1];
    switch (c) {
        case 's': case 'S': tag = 1; break;
        case 'm': case 'M': tag = 60; break;
        case 'h': case 'H': tag = 60 * 60; break;
        default: return;
    }
    [timeIntervalUnits selectItemAtIndex:
        [timeIntervalUnits indexOfItemWithTag: tag]];
    // NSLog(@"UPDATING FROM validation");
    [self update: timeInterval]; // make sure we still examine the field editor, otherwise if the existing numeric string is invalid, it'll be cleared
}

@end

@implementation PSAlarmSetController (NSWindowNotifications)

- (void)windowWillClose:(NSNotification *)notification;
{
    // NSLog(@"stopping update timer");
    [self _stopUpdateTimer];
}

@end

@implementation PSAlarmSetController (NSControlSubclassNotifications)

// called because we're the delegate

- (void)controlTextDidChange:(NSNotification *)notification;
{
    // NSLog(@"UPDATING FROM controlTextDidChange");
    [self update: [notification object]];
}

@end

@implementation PSAlarmSetController (NSApplicationDelegate)

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag;
{
    if (!flag) [self showWindow: self];
    return YES;
}

@end