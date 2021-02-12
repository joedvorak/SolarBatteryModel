% SAM data analysis
% Bo Smith, University of Kentucky
% January 20th, 2021

% This model is intended to estimate Battery storage for a specified
% solar energy system using an energy balance equation based off of 
% the law of conservation of energy.

% This system has inputs of estimated system load, estimate system battery
% capacity, and SAM produced system output data. This model will use a
% power balance to determine the presence of insufficient energy events,
% and provide a number of such events expected per year.

% Double check results against the minDOD model to make sure all indexing
% is correct.

clc;
clear;
close all;
% Simulation Variables
Eout= [0.25 0.5 0.75 1]; %System load in kW
% The panel and battery sizes must be used together. The first battery size
% will be used with the first panel size. The second with the second and so
% on.
E= [40];
%E= [5, 10, 15, 20, 30, 40, 50, 60]; %Initial Battery Storage estimate in kWh
panel = [20];
%panel = [20, 20, 20, 20, 20, 20, 20, 20]; % Panel Sizes
location = ["Cincinnati"];
StartMonth = 11; % Seasonal: Ignore starting on the 1st day of this month
EndMonth = 2; % Seasonal: Ignore stopping on the last day of this month
minDOD = .2;
invEff = 0.93; % Inverter Efficiency. 

% Initialize Data Variables - These are cell variables
timeStamp = cell(size(location,2),size(panel,2));
Ein1 = cell(size(location,2),size(panel,2));

%Import the SAM Data
for pidx = 1:size(panel,2)
    for li = 1:size(location,2)
        [timeStamp{li, pidx},Ein1{li, pidx}] = ...
            importSAMfile(join([location(li), "_", panel(pidx), "kW"],"")); %Array of system production values in kW
    end
end
%[timeStamp(pidx,location),Ein(pidx,location)] = importSAMfile("Jackson_5kW"); %Array of system production values in kW

Ebat = cell(size(location,2),size(panel,2),size(Eout,2));
fail = cell(size(location,2),size(panel,2),size(Eout,2));
EbatSeasonal = cell(size(location,2),size(panel,2),size(Eout,2));
failSeasonal = cell(size(location,2),size(panel,2),size(Eout,2));
runningSeason = cell(size(location,2),size(panel,2),size(Eout,2));
% These outputs are tables per location
eventPerYear = cell(size(location,2),1);
events = cell(size(location,2),1);
eventPerYearSeasonal = cell(size(location,2),1);
eventsSeasonal = cell(size(location,2),1);

% Process results
for li = 1:size(location,2)
    % Initialize Output tables for each location
    eventPerYear{li} = zeros(size(Eout,2),size(panel,2));
    events{li} = zeros(size(Eout,2),size(panel,2));
    eventPerYearSeasonal{li} = zeros(size(Eout,2),size(panel,2));
    eventsSeasonal{li} = zeros(size(Eout,2),size(panel,2));
    for pidx = 1:size(panel,2)
        for Ei = 1:size(Eout,2)
            Ebat{li, pidx, Ei}=zeros(1,numel(Ein{li, pidx})); %An array of zeros to be populated later
            fail{li, pidx, Ei}=zeros(1,numel(Ein{li, pidx}));
            Ebat{li, pidx, Ei}(1)=E(pidx); %This sets the initial battery value as being fully charged

            EbatSeasonal{li, pidx, Ei}=zeros(1,numel(Ein{li, pidx})); %An array of zeros to be populated later
            failSeasonal{li, pidx, Ei}=zeros(1,numel(Ein{li, pidx}));
            runningSeason{li, pidx, Ei}=true(1,numel(Ein{li, pidx}));
            EbatSeasonal{li, pidx, Ei}(1)=E(pidx); %This sets the initial battery value as being fully charged

            for i=1:(numel(Ein{li, pidx})-1)
                % Normal
                Ebat{li, pidx, Ei}(i+1)=(Ebat{li, pidx, Ei}(i)-Eout(Ei)/invEff)+Ein{li, pidx}(i);

                if Ebat{li, pidx, Ei}(i+1)>E(pidx)
                    Ebat{li, pidx, Ei}(i+1)=E(pidx);
                end 
                if Ebat{li, pidx, Ei}(i+1)<=(E(pidx) * 0.2)
                    fail{li, pidx, Ei}(i+1)=1;
                    Ebat{li, pidx, Ei}(i+1)=E(pidx);
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
                        EbatSeasonal{li, pidx, Ei}(i+1)=(EbatSeasonal{li, pidx, Ei}(i)-Eout(Ei)/invEff)+Ein{li, pidx}(i);

                        if EbatSeasonal{li, pidx, Ei}(i+1)>E(pidx)
                            EbatSeasonal{li, pidx, Ei}(i+1)=E(pidx);
                        end 
                        if EbatSeasonal{li, pidx, Ei}(i+1)<=(E(pidx) * 0.2)
                            failSeasonal{li, pidx, Ei}(i+1)=1;
                            EbatSeasonal{li, pidx, Ei}(i+1)=E(pidx);
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
                        EbatSeasonal{li, pidx, Ei}(i+1)=(EbatSeasonal{li, pidx, Ei}(i)-Eout(Ei))+Ein{li, pidx}(i);

                        if EbatSeasonal{li, pidx, Ei}(i+1)>E(pidx)
                            EbatSeasonal{li, pidx, Ei}(i+1)=E(pidx);
                        end 
                        if EbatSeasonal{li, pidx, Ei}(i+1)<=(E(pidx) * 0.2)
                            failSeasonal{li, pidx, Ei}(i+1)=1;
                            EbatSeasonal{li, pidx, Ei}(i+1)=E(pidx);
                        end
                    else
                        % Not operating
                        runningSeason{li, pidx, Ei}(i) = false;
                    end
                end
            end

            eventPerYear{li}(Ei, pidx)=(sum(fail{li, pidx, Ei})/21);
            events{li}(Ei, pidx) = sum(fail{li, pidx, Ei});

            eventPerYearSeasonal{li}(Ei, pidx)=(sum(failSeasonal{li, pidx, Ei})/21);
            eventsSeasonal{li}(Ei, pidx) = sum(failSeasonal{li, pidx, Ei});
        end
    end
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