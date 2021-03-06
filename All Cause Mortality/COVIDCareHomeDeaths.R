rm(list=ls())

library(tidyverse)
library(curl)
library(readxl)
library(forcats)
library(paletteer)
library(scales)
library(lubridate)

#Increment by 7 each week
MaxRange <- "JV"
#Increment by 1 each week
MaxRange2 <- "AO"

#Read in data on deaths in care home residents notified to CQC
#https://www.ons.gov.uk/peoplepopulationandcommunity/birthsdeathsandmarriages/deaths/datasets/numberofdeathsincarehomesnotifiedtothecarequalitycommissionengland/2020
temp <- tempfile()
source <- "https://www.ons.gov.uk/file?uri=%2fpeoplepopulationandcommunity%2fbirthsdeathsandmarriages%2fdeaths%2fdatasets%2fnumberofdeathsincarehomesnotifiedtothecarequalitycommissionengland%2f2021/cqcdata.xlsx"
temp <- curl_download(url=source, destfile=temp, quiet=FALSE, mode="wb")

#Deaths from COVID
data.COVID <- read_excel(temp, sheet="Table 2", range=paste0("A4:", MaxRange, "153"),
                         col_names=FALSE) %>% 
  gather(date, COVID, c(2:ncol(.))) %>% 
  mutate(date=as.Date("2020-04-10")+days(as.numeric(substr(date, 4,6))-2)) %>% 
  rename(name=`...1`)

#Deaths from all causes
data.all <- read_excel(temp, sheet="Table 3", range=paste0("A4:", MaxRange, "153"),
                       col_names=FALSE) %>% 
  gather(date, AllCause, c(2:ncol(.))) %>% 
  mutate(date=as.Date("2020-04-10")+days(as.numeric(substr(date, 4,6))-2))%>% 
  rename(name=`...1`)

#Combine
data <- merge(data.COVID, data.all) %>% 
  #Calculate other causes
  mutate(Other=AllCause-COVID, COVIDprop=if_else(is.na(COVID/AllCause), 0, COVID/AllCause)) %>% 
  gather(cause, deaths, c(3:5)) %>% 
  group_by(name, cause) %>% 
  mutate(deathsroll=roll_mean(deaths, 7, align="center", fill=NA),
         COVIDproproll=roll_mean(COVIDprop, 7, align="center", fill=NA),
         maxprop=max(COVIDproproll, na.rm=TRUE),
         maxpropday=date[which(COVIDproproll==maxprop)][1],
         cause=factor(cause, levels=c("Other", "COVID", "AllCause"))) 

data %>% 
  filter(name=="England" & cause!="AllCause" & !is.na(deathsroll)) %>% 
  ggplot()+
  geom_area(data=subset(data, name=="England" ),
            aes(x=date, y=deathsroll, fill=cause), position="stack")+
  scale_x_date(name="", breaks=pretty_breaks())+
  scale_y_continuous(name="Daily deaths in care homes")+
  scale_fill_paletteer_d("NineteenEightyR::malibu")+
  theme_classic()

plotfrom=min(data$date[!is.na(data$deathsroll)])
plotto=max(data$date[!is.na(data$deathsroll)])

tiff("Outputs/ONSCQCDeathsxCause.tiff", units="in", width=8, height=6, res=500)
ggplot()+
  geom_area(data=subset(data, name=="England" & cause=="COVID" & !is.na(deathsroll)),
            aes(x=date, y=deathsroll), fill="#F44B4B")+
  geom_area(data=subset(data, name=="England" & cause=="Other" & !is.na(deathsroll)),
            aes(x=date, y=-deathsroll), fill="#F19743")+
  geom_hline(yintercept=0)+
  scale_x_date(name="", breaks=pretty_breaks(n=interval(as.Date(plotfrom), plotto)%/% months(1)))+
  scale_y_continuous(name="Daily deaths in care homes", labels=abs)+
  theme_classic()+
  theme(plot.title=element_text(face="bold", size=rel(1.2)),
        plot.subtitle=element_markdown())+
  labs(title="The increase in COVID-19 deaths in care homes in England is accelerating",
       subtitle="Deaths from <span style='color:#F44B4B;'>COVID-19</span> and <span style='color:#F19743;'>all other causes</span> notified to the Care Quality Commission, by date of notification",
       caption="Data from ONS | Plot by @VictimOfMaths")
dev.off()

#Read in place of death data for care home residents
#Deaths from All Causes
data.COVID.2 <- read_excel(temp, sheet="Table 4", range=paste0("A6:", MaxRange2, "9"),
                         col_names=FALSE) %>% 
  gather(week, AllCause, c(2:ncol(.))) %>% 
  mutate(week=as.numeric(substr(week, 4,6))+14,
         location=case_when(
           `...1` %in% c("Elsewhere", "Not Stated") ~ "Other/Unknown",
           TRUE ~ `...1`)) %>% 
  group_by(week, location) %>% 
  mutate(AllCause=as.numeric(AllCause)) %>% 
  summarise(AllCause=sum(AllCause)) %>% 
  ungroup()

#Deaths from COVID  
data.all.2 <- read_excel(temp, sheet="Table 4", range=paste0("A12:", MaxRange2, "15"),
                         col_names=FALSE) %>% 
  gather(week, COVID, c(2:ncol(.))) %>% 
  mutate(week=as.numeric(substr(week, 4,6))+14,
         location=case_when(
           `...1` %in% c("Elsewhere", "Not Stated") ~ "Other/Unknown",
           TRUE ~ `...1`)) %>% 
  group_by(week, location) %>% 
  mutate(COVID=as.numeric(COVID)) %>% 
  summarise(COVID=sum(COVID)) %>% 
  ungroup() %>% 
  #Merge
  merge(data.COVID.2) %>% 
  mutate(Other=AllCause-COVID) %>% 
  gather(cause, deaths, c(3:5)) %>% 
  mutate(causeloc=case_when(
    cause=="COVID" ~ paste0("COVID-19 deaths in ", location),
    cause=="Other" ~ paste0("Other cause deaths in ", location)),
    date=as.Date("2020-04-13")+days(7*(week-16)))

tiff("Outputs/ONSCQCDeathsxCausexLoc.tiff", units="in", width=8, height=6, res=500)
ggplot(subset(data.all.2, cause!="AllCause"))+
  geom_col(aes(x=date, y=deaths, fill=causeloc))+
  scale_x_date(name="", breaks=pretty_breaks(n=interval(as.Date(plotfrom), plotto)%/% months(1)))+
  scale_y_continuous(name="Deaths of care home residents")+
  scale_fill_manual(values=c("#C70E7B", "#007BC3", "#EF7C12", "#FC6882", "#54BCD1", "#F4B95A"),
                    name="Cause and place of death")+
  theme_classic()+
  theme(plot.title=element_text(face="bold", size=rel(1.2)))+
  labs(title="Most COVID-19 deaths of care home residents are happening in care homes",
       subtitle="Weekly deaths notified to the Care Quality Commission of care home residents\nby cause and location.",
       caption="Data from ONS | Plot by @VictimOfMaths")
dev.off()

#WIP heatmap
tiff("Outputs/ONSCQCDeathsHeatmap.tiff", units="in", width=13, height=14, res=500)
data %>% 
  filter(name!="England" & cause=="AllCause" & !is.na(COVIDproproll)) %>% 
  ggplot()+
  geom_tile(aes(x=date, y=fct_reorder(name, maxpropday), fill=COVIDproproll))+
  theme_classic()+
  scale_fill_paletteer_c("pals::ocean.haline", name="Proportion of deaths\ninvolving COVID",
                         labels=scales::percent)+
  scale_y_discrete(name="")+
  scale_x_date(name="")+
  theme(plot.title=element_text(face="bold", size=rel(1.2)))+
  labs(title="The number of Local Authorities reporting a substantial proportion of deaths in care homes as COVID-related is rising",
       subtitle="Proportion of deaths in care homes notified to CQC recorded as involving COVID-19 by Local Authority in England.\nAuthorities are ordered by the date on which the highest proportion of deaths involved COVID-19.",
       caption="Data from ONS | Plot by @VictimOfMaths")
dev.off()
