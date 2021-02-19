% SAM data analysis
% Bo Smith, University of Kentucky
% January 20th, 2021

% This model incorporates solar, battery, and generator backup.

% This model is intended to estimate Battery storage for a specified
% solar energy system using an energy balance equation based off of 
% the law of conservation of energy.

% This system has inputs of estimated system load, estimate system battery
% capacity, and SAM produced system output data. This model will use a
% power balance to determine the battery State of Charge. If the battery
% reaches a minimum value, a generator is used to restore power to a
% minimum level.

% Double check results against the minDOD model to make sure all indexing
% is correct.

clc;
clear;
close all;
% Simulation Variables
% Eout= [0.75]; %System load in kW
Eout= [0.25 0.5 0.75 1]; %System load in kW
% The panel and battery sizes must be used together. The first battery size
% will be used with the first panel size. The second with the second and so
% on.
% E= [5, 10, 15, 20];
E= [5, 10, 15, 20, 30, 40, 50, 60 ...
    5, 10, 15, 20, 30, 40, 50, 60 ...
    5, 10, 15, 20, 30, 40, 50, 60 ...
    5, 10, 15, 20, 30, 40, 50, 60 ...
    5, 10, 15, 20, 30, 40, 50, 60 ...
    5, 10, 15, 20, 30, 40, 50, 60 ...
    5, 10, 15, 20, 30, 40, 50, 60 ...
    ]; %Initial Battery Storage estimate in kWh
% panel = [2, 2, 2, 2];
panel = [2, 2, 2, 2, 2, 2, 2, 2 ...
    3, 3, 3, 3, 3, 3, 3, 3 ...
    4, 4, 4, 4, 4, 4, 4, 4 ...
    5, 5, 5, 5, 5, 5, 5, 5 ...
    10, 10, 10, 10, 10, 10, 10, 10 ...
    15, 15, 15, 15, 15, 15, 15, 15 ...
    20, 20, 20, 20, 20, 20, 20, 20 ...
    ]; % Panel Sizes
location = ["Lexington"];
% location = ["Bowling Green", "Cincinnati", "Jackson", "Lexington", "London", "Louisville", "Paducah"];
StartMonth = 11; % Seasonal: Ignore starting on the 1st day of this month
EndMonth = 2; % Seasonal: Ignore stopping on the last day of this month
minDOD = .2;
invEff = 0.93; % Inverter Efficiency. (From DC to AC)
charConEff = 0.97; % Charge Controller Efficiency (From PV to DC)
DoDlimit = 0.2; % This is the minimum acceptable Depth of Discharge
genOutput = 2; % The output of the generator in kW
genShutOffLevel = 0.85; % The generator turns on at the DoDlimit and runs until this level
genOn = false; % Flag to determine if the generator is on.
genOnSeason = false; % Flag to determine if the generator is on (Seasonal)

% Battery Efficiency
battCharEff = 0.85; % Efficiency of adding charge to the battery
% This model assumes constant charging and discharging rates for each hour.
% If the power input from solar is greater than the power output to the
% load, then the system is charging. This efficiency is used. The
% efficiency only applies to the power difference as this is what goes to
% the battery.
% If the power input from solar is less than the power output to the
% load, then the system is discharging. This value does not apply in
% discharging.

% Initialize Data Variables - These are cell variables
timeStamp = cell(size(location,2),size(panel,2));
Ein = cell(size(location,2),size(panel,2));

%Import the SAM Data
for pidx = 1:size(panel,2)
    for li = 1:size(location,2)
        [timeStamp{li, pidx},Ein{li, pidx}] = ...
            importSAMfile(join([location(li), "_", panel(pidx), "kW"],"")); %Array of system production values in kW
    end
end

Ebat = cell(size(location,2),size(panel,2),size(Eout,2));
genRun = cell(size(location,2),size(panel,2),size(Eout,2));
EbatSeasonal = cell(size(location,2),size(panel,2),size(Eout,2));
genRunSeasonal = cell(size(location,2),size(panel,2),size(Eout,2));
runningSeason = cell(size(location,2),size(panel,2),size(Eout,2));
% These outputs are tables per location
genHoursPerYear = cell(size(location,2),1);
genHours = cell(size(location,2),1);
genHoursPerYearSeasonal = cell(size(location,2),1);
genHoursSeasonal = cell(size(location,2),1);

% Process results
for li = 1:size(location,2)
    % Initialize Output tables for each location
    genHoursPerYear{li} = zeros(size(Eout,2),size(panel,2));
    genHours{li} = zeros(size(Eout,2),size(panel,2));
    genHoursPerYearSeasonal{li} = zeros(size(Eout,2),size(panel,2));
    genHoursSeasonal{li} = zeros(size(Eout,2),size(panel,2));
    for pidx = 1:size(panel,2)
        for Ei = 1:size(Eout,2)
            Ebat{li, pidx, Ei}=zeros(1,numel(Ein{li, pidx})); %An array of zeros to be populated later
            genRun{li, pidx, Ei}=zeros(1,numel(Ein{li, pidx}));
            Ebat{li, pidx, Ei}(1)=E(pidx); %This sets the initial battery value as being fully charged

            EbatSeasonal{li, pidx, Ei}=zeros(1,numel(Ein{li, pidx})); %An array of zeros to be populated later
            genRunSeasonal{li, pidx, Ei}=zeros(1,numel(Ein{li, pidx}));
            runningSeason{li, pidx, Ei}=true(1,numel(Ein{li, pidx}));
            EbatSeasonal{li, pidx, Ei}(1)=E(pidx); %This sets the initial battery value as being fully charged
            
            genOn = false; % Ensure Generator starts off.
            genOnSeason = false; % Ensure Generator starts off.

            for i=1:(numel(Ein{li, pidx})-1)
                % Normal
                if (Ein{li, pidx}(i)+genOn*genOutput)*charConEff>Eout(Ei)/invEff
                    % charging - some power into battery and affected by
                    % battery charging efficiency
                    Ebat{li, pidx, Ei}(i+1)=Ebat{li, pidx, Ei}(i)+((Ein{li, pidx}(i)+genOn*genOutput)*charConEff-Eout(Ei)/invEff)*battCharEff;
                else
                    % discharging - all power direct to load
                    Ebat{li, pidx, Ei}(i+1)=Ebat{li, pidx, Ei}(i)+(Ein{li, pidx}(i)+genOn*genOutput)*charConEff-Eout(Ei)/invEff;
                end

                if Ebat{li, pidx, Ei}(i+1)>E(pidx) % Cannot be more than 100% charged.
                    Ebat{li, pidx, Ei}(i+1)=E(pidx);
                end 
                if Ebat{li, pidx, Ei}(i+1)<=(E(pidx) * DoDlimit) % Detect when minimum is reached
                    genOn = true; % Turn on generator
                end
                if genOn == true
                    genRun{li, pidx, Ei}(i+1)=true; % Record that the generator is on
                    if Ebat{li, pidx, Ei}(i+1)>= genShutOffLevel*E(pidx) % We have reached shutoff level
                        genOn = false; % Stop Generator
                    end
                end
                % Seasonal
                cur_m = month(timeStamp{li, pidx}(i));
                if StartMonth > EndMonth
                    % Loop around January
                    if ((cur_m < StartMonth) && (cur_m > EndMonth))
                        % Operating Period
                        runningSeason{li, pidx, Ei}(i) = true;
                        if i~=1 % Matlab doesn't loop like python. Can't check initial state.    
                            if runningSeason{li, pidx, Ei}(i) && not(runningSeason{li, pidx, Ei}(i-1))
                                % Restarting with full battery
                                EbatSeasonal{li, pidx, Ei}(i)=E(pidx);
                            end
                        end
                        if (Ein{li, pidx}(i)+genOnSeason*genOutput)*charConEff>Eout(Ei)/invEff
                            % charging
                            EbatSeasonal{li, pidx, Ei}(i+1)=EbatSeasonal{li, pidx, Ei}(i)+((Ein{li, pidx}(i)+genOnSeason*genOutput)*charConEff-Eout(Ei)/invEff)*battCharEff;
                        else
                            % discharging
                            EbatSeasonal{li, pidx, Ei}(i+1)=EbatSeasonal{li, pidx, Ei}(i)+(Ein{li, pidx}(i)+genOnSeason*genOutput)*charConEff-Eout(Ei)/invEff;
                        end

                        if EbatSeasonal{li, pidx, Ei}(i+1)>E(pidx) % Cannot be more than 100% charged.
                            EbatSeasonal{li, pidx, Ei}(i+1)=E(pidx);
                        end 
                        if EbatSeasonal{li, pidx, Ei}(i+1)<=(E(pidx) * DoDlimit) % Detect when minimum is reached
                            genOnSeason = true; % Turn on generator
                        end
                    if genOnSeason == true
                        genRunSeasonal{li, pidx, Ei}(i+1)=true; % Record that the generator is on
                        if EbatSeasonal{li, pidx, Ei}(i+1)>= genShutOffLevel*E(pidx) % We have reached shutoff level
                            genOnSeason = false; % Stop Generator
                        end
                    end
                    else
                        % Not operating
                        runningSeason{li, pidx, Ei}(i) = false;
                    end
                else
                    % In the same calendar year
                    if ((cur_m < StartMonth) || (cur_m > EndMonth))
                        % Operating Period
                        runningSeason{li, pidx, Ei}(i) = true;
                        if i~=1 % Matlab doesn't loop like python. Can't check initial state.    
                            if runningSeason{li, pidx, Ei}(i) && not(runningSeason{li, pidx, Ei}(i-1))
                                % Restarting with full battery
                                EbatSeasonal{li, pidx, Ei}(i)=E(pidx);
                            end
                        end
                        if (Ein{li, pidx}(i)+genOnSeason*genOutput)*charConEff>Eout(Ei)/invEff
                            % charging
                            EbatSeasonal{li, pidx, Ei}(i+1)=EbatSeasonal{li, pidx, Ei}(i)+((Ein{li, pidx}(i)+genOnSeason*genOutput)*charConEff-Eout(Ei)/invEff)*battCharEff;
                        else
                            % discharging
                            EbatSeasonal{li, pidx, Ei}(i+1)=EbatSeasonal{li, pidx, Ei}(i)+(Ein{li, pidx}(i)+genOnSeason*genOutput)*charConEff-Eout(Ei)/invEff;
                        end
                        if EbatSeasonal{li, pidx, Ei}(i+1)>E(pidx) % Cannot be more than 100% charged.
                            EbatSeasonal{li, pidx, Ei}(i+1)=E(pidx);
                        end 
                        if EbatSeasonal{li, pidx, Ei}(i+1)<=(E(pidx) * DoDlimit) % Detect when minimum is reached
                            genOnSeason = true; % Turn on generator
                        end
                    if genOnSeason == true
                        genRunSeasonal{li, pidx, Ei}(i+1)=true; % Record that the generator is on
                        if EbatSeasonal{li, pidx, Ei}(i+1)>= genShutOffLevel*E(pidx) % We have reached shutoff level
                            genOnSeason = false; % Stop Generator
                        end
                    end
                    else
                        % Not operating
                        runningSeason{li, pidx, Ei}(i) = false;
                    end
                end
            end

            genHoursPerYear{li}(Ei, pidx)=(sum(genRun{li, pidx, Ei})/21);
            genHours{li}(Ei, pidx) = sum(genRun{li, pidx, Ei});

            genHoursPerYearSeasonal{li}(Ei, pidx)=(sum(genRunSeasonal{li, pidx, Ei})/21);
            genHoursSeasonal{li}(Ei, pidx) = sum(genRunSeasonal{li, pidx, Ei});
        end
    end
end

tableheaderYear = ["Generator Operating Hours over 21 Years (All Year)", "Batt Size (kWh) [E]", "panel size (kw)", Eout+" kW Load"]';
tableheaderSeason = [["Generator Operating Hours over 21 Years (Seasonal: Month "+StartMonth+" to "+EndMonth+")"], "Batt Size (kWh) [E]", "panel size (kw)", Eout+" kW Load"]';

tableSeasonStart = size(tableheaderYear,1)+2;


for li = 1:size(location,2)
    filename = 'GenTables.xlsx';
    % All year data
    writematrix(tableheaderYear,filename,'Sheet', location(li),'Range','A1','WriteMode','overwritesheet'); % Erases the worksheet first
    writematrix(E,filename,'Sheet', location(li),'Range','B2');
    writematrix(panel,filename,'Sheet', location(li),'Range','B3');
    writematrix(genHours{li},filename,'Sheet', location(li),'Range','B4');
    
    writematrix(tableheaderSeason,filename,'Sheet', location(li),'Range',["A"+tableSeasonStart]);
    writematrix(E,filename,'Sheet', location(li),'Range',["B"+(tableSeasonStart+1)]);
    writematrix(panel,filename,'Sheet', location(li),'Range',["B"+(tableSeasonStart+2)]);
    writematrix(genHoursSeasonal{li},filename,'Sheet', location(li),'Range',["B"+(tableSeasonStart+3)]);
end

% The outputs will be in four tables. The tables are cell arrays with each
% corresponding to a location. They are in order of the location list.
% For each location, the rows are loads (Eout), and the columns are the
% panel/battery system sizes (panel+E). The first column will be for the
% first value in both the panel and battery size (E) array. The second will
% be for the second set of values in each array (E(2) and panel(2), and so
% on.

% To plot results use:
% plot(timeStamp{li, pidx}, Ebat{li, pidx, Ei})
% You can use the plot commands above for any of the variables that are
% generated for each hour of input data. Set li, pidx, Ei to the indexes
% that you want to plot. Ei is for the Eout array (e.g. Ei = 2, will plot 
% the result with the second value in Eout). pidx is for the panel and E
% arrays. li is for the location array.

% Other variables to plot.
% plot(timeStamp{li, pidx}, runningSeason{li, pidx, Ei})
% plot(timeStamp{li, pidx}, fail{li, pidx, Ei})